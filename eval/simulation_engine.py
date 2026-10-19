"""
Smart Parking System (SLIIT J26-IT-335)
Reproducibility Simulation Engine

Simulates a 24-hour diurnal cycle with Poisson arrivals, Gaussian delays,
stochastic no-shows, and exact scoring policy evaluation.
Guarantees identical trip streams across policies for paired statistical testing.
"""

import copy
import math
import random
from typing import Dict, Any, List, Optional, Tuple
from eval.policies import BasePolicy

def build_facility(config: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    fac_cfg = config.get("facility", {})
    total_slots = fac_cfg.get("total_slots", 72)
    layout = fac_cfg.get("layout", {})
    row_distances = layout.get("row_distances_meters", {})
    covered_count = fac_cfg.get("covered_slots_count", 24)
    slot_sizes = fac_cfg.get("slot_sizes", {"small": 42, "medium": 22, "large": 8})

    # Prepare size pool
    sizes = (
        ["small"] * slot_sizes.get("small", 42)
        + ["medium"] * slot_sizes.get("medium", 22)
        + ["large"] * slot_sizes.get("large", 8)
    )

    slots: List[Dict[str, Any]] = []
    slot_idx = 0
    row_names = sorted(row_distances.keys())

    for r_name in row_names:
        distances = row_distances[r_name]
        for d in distances:
            if slot_idx >= total_slots:
                break
            s_id = f"slot-{r_name.lower()}-{slot_idx + 1:02d}"
            s_type = "covered" if slot_idx < covered_count else "standard"
            s_size = sizes[slot_idx] if slot_idx < len(sizes) else "medium"

            slots.append({
                "id": s_id,
                "row": r_name,
                "size": s_size,
                "type": s_type,
                "walkingDistanceMeters": float(d),
                "state": "available",
                "currentBookingId": None,
                "lastOccupiedAt": None,
            })
            slot_idx += 1

    lot = {
        "id": fac_cfg.get("lot_id", "lot-colombo-01"),
        "totalSlots": len(slots),
        "freeSlots": len(slots),
    }
    return slots, lot


def generate_trip_stream(
    seed: int,
    config: Dict[str, Any],
    demand_per_hour_override: Optional[float] = None,
    no_show_rate_override: Optional[float] = None,
    mean_delay_override: Optional[float] = None,
) -> List[Dict[str, Any]]:
    rng = random.Random(seed)

    dem_cfg = config.get("demand", {})
    stoch_cfg = config.get("stochastic_driver", {})

    base_demand = demand_per_hour_override if demand_per_hour_override is not None else dem_cfg.get("baseline_drivers_per_hour", 60)
    hourly_multipliers = dem_cfg.get("hourly_profile", [1.0] * 24)
    no_show_rate = no_show_rate_override if no_show_rate_override is not None else stoch_cfg.get("no_show_rate_default", 0.12)
    mean_delay = mean_delay_override if mean_delay_override is not None else stoch_cfg.get("mean_delay_minutes_default", 3.5)
    std_delay = stoch_cfg.get("delay_std_minutes", 4.0)
    duration_mean = stoch_cfg.get("parking_duration_hours_mean", 2.2)
    duration_std = stoch_cfg.get("parking_duration_hours_std", 1.0)

    trips: List[Dict[str, Any]] = []
    trip_counter = 0

    for hour in range(24):
        lam = base_demand * hourly_multipliers[hour]
        # Generate Poisson arrivals for this hour via Knuth algorithm
        L = math.exp(-lam)
        k = 0
        p = 1.0
        while True:
            k += 1
            p *= rng.random()
            if p <= L:
                break
        n_arrivals = k - 1

        for _ in range(n_arrivals):
            trip_counter += 1
            # Arrival time within hour
            sec_in_hour = rng.uniform(0, 3600)
            request_time_sec = hour * 3600 + sec_in_hour

            # Travel ETA: between 15 and 35 minutes
            eta_minutes = rng.uniform(15.0, 35.0)

            # Delay in traffic (Gaussian >= 0)
            delay_minutes = max(0.0, rng.gauss(mean_delay, std_delay))

            # No-show indicator
            is_no_show = rng.random() < no_show_rate

            # Planned parking dwell duration (min 30 mins)
            dwell_hours = max(0.5, rng.gauss(duration_mean, duration_std))
            dwell_seconds = dwell_hours * 3600.0

            # Vehicle size distribution (60% small, 30% medium, 10% large)
            v_roll = rng.random()
            if v_roll < 0.60:
                v_size = "small"
            elif v_roll < 0.90:
                v_size = "medium"
            else:
                v_size = "large"

            # Covered parking preference (20% prefer covered)
            pref_covered = rng.random() < 0.20

            # Random scalar for acceptance model (guarantees identical acceptance decisions)
            acc_rand = rng.random()

            trips.append({
                "trip_id": f"trip-{seed}-{trip_counter:04d}",
                "request_time_sec": request_time_sec,
                "initial_eta_minutes": eta_minutes,
                "delay_minutes": delay_minutes,
                "is_no_show": is_no_show,
                "parking_duration_sec": dwell_seconds,
                "vehicle": {"size": v_size},
                "preferences": {"coveredParkingOnly": pref_covered},
                "acceptance_rand": acc_rand,
            })

    trips.sort(key=lambda t: t["request_time_sec"])
    return trips


def run_simulation(
    policy: BasePolicy,
    trips: List[Dict[str, Any]],
    config: Dict[str, Any],
    acceptance_model_override: Optional[float] = None,
) -> Dict[str, Any]:
    slots, lot = build_facility(config)
    slot_map = {s["id"]: s for s in slots}

    hold_duration_sec = config.get("policies", {}).get("hold_duration_minutes", 15.0) * 60.0
    in_transit_trigger_eta = config.get("policies", {}).get("in_transit_trigger_eta_minutes", 10.0)

    # Active states
    active_reservations: Dict[str, Dict[str, Any]] = {}
    completed_bookings: List[Dict[str, Any]] = []
    rejected_count = 0
    auto_released_count = 0
    upgrades_offered = 0
    upgrades_accepted = 0
    total_slot_sec_recovered = 0.0

    # Hourly metrics tracking
    hourly_occupied: List[float] = [0.0] * 24
    peak_hours = {8, 9, 16, 17}
    peak_completions = 0

    # Collect discrete time events: (time_sec, event_type, payload)
    # Types:
    #   'REQUEST' (trip requests reservation)
    #   'IN_TRANSIT_EVAL' (driver reaches 10-min ETA threshold)
    #   'EXPIRE_HOLD' (15 min after scheduled arrival)
    #   'ACTUAL_ARRIVAL' (driver arrives at lot)
    #   'DEPARTURE' (driver finishes parking and leaves)

    events: List[Tuple[float, str, Any]] = []
    for t in trips:
        events.append((t["request_time_sec"], "REQUEST", t))

    events.sort(key=lambda e: e[0])

    sim_duration_sec = 24 * 3600.0

    def sync_lot_free_slots():
        lot["freeSlots"] = sum(1 for s in slots if s["state"] == "available")

    while events:
        time_sec, ev_type, data = events.pop(0)
        if time_sec > sim_duration_sec + 7200.0:  # Allow trailing checkouts
            break

        hour_idx = min(23, int(time_sec // 3600)) if time_sec >= 0 else 0
        sync_lot_free_slots()

        if ev_type == "REQUEST":
            trip = data
            selected_slot = policy.select_initial_slot(slots, lot, trip["vehicle"], trip["preferences"])
            if not selected_slot:
                rejected_count += 1
                continue

            # Allocate slot
            s_obj = slot_map[selected_slot["id"]]
            s_obj["state"] = "reserved"
            s_obj["currentBookingId"] = trip["trip_id"]
            sync_lot_free_slots()

            scheduled_arr = trip["request_time_sec"] + (trip["initial_eta_minutes"] * 60.0)
            actual_arr = scheduled_arr + (trip["delay_minutes"] * 60.0)
            eval_time = max(trip["request_time_sec"], scheduled_arr - (in_transit_trigger_eta * 60.0))
            hold_expire_time = scheduled_arr + hold_duration_sec

            res_record = {
                "trip": trip,
                "slot_id": s_obj["id"],
                "initial_slot_id": s_obj["id"],
                "status": "reserved",
                "scheduled_arrival_sec": scheduled_arr,
                "actual_arrival_sec": actual_arr,
                "hold_expire_sec": hold_expire_time,
                "eval_time_sec": eval_time,
                "departure_sec": actual_arr + trip["parking_duration_sec"],
                "upgraded": False,
                "distance_saved_m": 0.0,
            }
            active_reservations[trip["trip_id"]] = res_record

            # Schedule in-transit upgrade check
            events.append((eval_time, "IN_TRANSIT_EVAL", trip["trip_id"]))
            # Schedule auto-release timeout
            events.append((hold_expire_time, "EXPIRE_HOLD", trip["trip_id"]))
            # Schedule actual arrival (if not no-show)
            if not trip["is_no_show"]:
                events.append((actual_arr, "ACTUAL_ARRIVAL", trip["trip_id"]))

            events.sort(key=lambda e: e[0])

        elif ev_type == "IN_TRANSIT_EVAL":
            b_id = data
            res = active_reservations.get(b_id)
            if not res or res["status"] != "reserved":
                continue

            current_s = slot_map[res["slot_id"]]
            eta_now_min = max(0.0, (res["scheduled_arrival_sec"] - time_sec) / 60.0)

            available_cand = [s for s in slots if s["state"] == "available"]
            accepted, best_s, dist_saved, score_diff = policy.evaluate_upgrade(
                current_slot=current_s,
                candidate_slots=available_cand,
                lot=lot,
                vehicle=res["trip"]["vehicle"],
                preferences=res["trip"]["preferences"],
                eta_minutes=eta_now_min,
                acceptance_model_override=acceptance_model_override,
                acceptance_rand=res["trip"]["acceptance_rand"],
            )

            if best_s is not None:
                upgrades_offered += 1
                if accepted:
                    upgrades_accepted += 1
                    # Swap slots atomically
                    current_s["state"] = "available"
                    current_s["currentBookingId"] = None

                    target_s = slot_map[best_s["id"]]
                    target_s["state"] = "reserved"
                    target_s["currentBookingId"] = b_id

                    res["slot_id"] = target_s["id"]
                    res["upgraded"] = True
                    res["distance_saved_m"] = dist_saved
                    sync_lot_free_slots()

        elif ev_type == "EXPIRE_HOLD":
            b_id = data
            res = active_reservations.get(b_id)
            if not res or res["status"] != "reserved":
                continue

            # Check if policy dictates auto-release
            if policy.should_auto_release(res, time_sec, hold_duration_sec):
                res["status"] = "auto_released"
                s_obj = slot_map[res["slot_id"]]
                s_obj["state"] = "available"
                s_obj["currentBookingId"] = None
                auto_released_count += 1
                sync_lot_free_slots()

                # Slot minutes recovered = planned session that is no longer held
                time_saved_sec = max(0.0, res["departure_sec"] - time_sec)
                total_slot_sec_recovered += time_saved_sec
            else:
                # B0 / D1: slot stays locked until planned departure even if no-show
                if res["trip"]["is_no_show"]:
                    res["status"] = "no_show_held"
                    # Release only at planned departure
                    events.append((res["departure_sec"], "DEPARTURE_NO_SHOW", b_id))
                    events.sort(key=lambda e: e[0])

        elif ev_type == "ACTUAL_ARRIVAL":
            b_id = data
            res = active_reservations.get(b_id)
            if not res or res["status"] != "reserved":
                continue  # Driver was auto-released or cancelled

            res["status"] = "occupied"
            s_obj = slot_map[res["slot_id"]]
            s_obj["state"] = "occupied"
            s_obj["lastOccupiedAt"] = time_sec
            sync_lot_free_slots()

            events.append((res["departure_sec"], "DEPARTURE", b_id))
            events.sort(key=lambda e: e[0])

        elif ev_type == "DEPARTURE":
            b_id = data
            res = active_reservations.get(b_id)
            if not res:
                continue

            res["status"] = "completed"
            s_obj = slot_map[res["slot_id"]]
            s_obj["state"] = "available"
            s_obj["currentBookingId"] = None
            sync_lot_free_slots()

            completed_bookings.append(res)
            active_reservations.pop(b_id, None)

            if hour_idx in peak_hours:
                peak_completions += 1

        elif ev_type == "DEPARTURE_NO_SHOW":
            b_id = data
            res = active_reservations.get(b_id)
            if not res:
                continue
            s_obj = slot_map[res["slot_id"]]
            s_obj["state"] = "available"
            s_obj["currentBookingId"] = None
            sync_lot_free_slots()
            active_reservations.pop(b_id, None)

    # Compute Final Performance Metrics
    total_trips = len(trips)
    n_completed = len(completed_bookings)
    rejection_rate_pct = (rejected_count / total_trips * 100.0) if total_trips > 0 else 0.0

    mean_walk = (
        sum(slot_map[b["slot_id"]]["walkingDistanceMeters"] for b in completed_bookings) / n_completed
        if n_completed > 0
        else 0.0
    )

    walk_saved_mean = (
        sum(b["distance_saved_m"] for b in completed_bookings) / n_completed
        if n_completed > 0
        else 0.0
    )

    acceptance_pct = (
        (upgrades_accepted / upgrades_offered * 100.0) if upgrades_offered > 0 else 0.0
    )

    slot_minutes_recovered = total_slot_sec_recovered / 60.0
    total_capacity = lot["totalSlots"]
    turnover_at_peak = peak_completions / float(total_capacity)

    # Average lot utilization across 24h
    occupied_slots_mean = (
        sum(b["trip"]["parking_duration_sec"] for b in completed_bookings) / sim_duration_sec
    )
    lot_utilisation_pct = (occupied_slots_mean / total_capacity * 100.0) if total_capacity > 0 else 0.0

    return {
        "policy": policy.name,
        "total_requests": total_trips,
        "completed_parkings": n_completed,
        "rejections": rejected_count,
        "rejection_rate_pct": round(rejection_rate_pct, 2),
        "mean_walking_distance_m": round(mean_walk, 2),
        "walking_distance_saved_mean_m": round(walk_saved_mean, 2),
        "slot_minutes_recovered": round(slot_minutes_recovered, 1),
        "lot_utilisation_pct": round(lot_utilisation_pct, 2),
        "turnover_at_peak": round(turnover_at_peak, 3),
        "upgrades_offered": upgrades_offered,
        "upgrades_accepted": upgrades_accepted,
        "upgrade_acceptance_pct": round(acceptance_pct, 2),
    }

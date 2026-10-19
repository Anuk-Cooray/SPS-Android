"""
Smart Parking System (SLIIT J26-IT-335)
Mathematical Formulation of the Algorithmic Multi-Criteria Scoring Engine
100% Parity with Dart ReoptimizationEngine and TypeScript scoring.ts
"""

from typing import Dict, Any, List, Optional, Tuple

MAX_WALKING_METERS = 250.0

DEFAULT_WEIGHTS = {
    "distance_weight": 0.40,
    "size_fit_weight": 0.25,
    "preference_weight": 0.20,
    "demand_weight": 0.15,
    "min_improvement_meters": 50.0,
    "min_score_improvement_points": 20.0,
    "upgrade_trigger_eta_minutes": 10.0,
    "offer_timeout_seconds": 60.0,
}

def clamp(val: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(val, max_val))

def is_size_compatible(slot_size: str, vehicle_size: str) -> bool:
    size_ranks = {"small": 1, "medium": 2, "large": 3}
    return size_ranks.get(slot_size, 0) >= size_ranks.get(vehicle_size, 0)

def score_slot(
    slot: Dict[str, Any],
    lot: Dict[str, Any],
    vehicle: Dict[str, Any],
    preferences: Dict[str, Any],
    weights: Optional[Dict[str, float]] = None,
) -> Dict[str, Any]:
    w = DEFAULT_WEIGHTS.copy()
    if weights:
        w.update(weights)

    slot_size = slot.get("size", "medium")
    vehicle_size = vehicle.get("size", "medium")

    # 1. Size Compatibility Check
    if not is_size_compatible(slot_size, vehicle_size):
        return {
            "slot": slot,
            "is_eligible": False,
            "total_score": 0.0,
            "distance_score": 0.0,
            "size_fit_score": 0.0,
            "preference_score": 0.0,
            "demand_penalty": 0.0,
            "explanation": f"Slot size ({slot_size}) is too small for vehicle ({vehicle_size})",
        }

    # 2. Normalized Walking Distance Score (0 - 100)
    walking_dist = float(slot.get("walkingDistanceMeters", 0))
    distance_ratio = clamp(MAX_WALKING_METERS - walking_dist, 0.0, MAX_WALKING_METERS) / MAX_WALKING_METERS
    distance_score = distance_ratio * 100.0

    # 3. Size Fit Score (0 - 100)
    if slot_size == vehicle_size:
        size_fit_score = 100.0
    elif vehicle_size == "small" and slot_size == "large":
        size_fit_score = 60.0
    elif vehicle_size == "medium" and slot_size == "large":
        size_fit_score = 80.0
    elif vehicle_size == "small" and slot_size == "medium":
        size_fit_score = 85.0
    else:
        size_fit_score = 100.0

    # 4. User Preference Score (0 - 100)
    # Non-distance categorical preferences (avoids double-counting distance)
    preference_score = 50.0  # baseline neutral
    covered_only = preferences.get("coveredParkingOnly", False)
    if covered_only:
        if slot.get("type") == "covered":
            preference_score = 100.0
        else:
            preference_score = 10.0
    preference_score = clamp(preference_score, 0.0, 100.0)

    # 5. Lot Demand Factor (0 - 100) — Slot-aware demand penalty
    total_slots = float(lot.get("totalSlots", 1))
    free_slots = float(lot.get("freeSlots", 0))
    occupancy_rate = (total_slots - free_slots) / total_slots if total_slots > 0 else 0.0

    turnover_multiplier = 1.0
    if occupancy_rate >= 0.70 and walking_dist <= 50.0:
        turnover_multiplier = 1.20  # High-turnover entrance zone during peak demand
    elif walking_dist > 150.0:
        turnover_multiplier = 0.80  # Deep perimeter zone

    base_demand = occupancy_rate * 25.0
    demand_penalty = clamp(base_demand * turnover_multiplier, 0.0, 100.0)

    # 6. Linear Weighted Summation (SYS-01)
    raw_total = (
        w["distance_weight"] * distance_score
        + w["size_fit_weight"] * size_fit_score
        + w["preference_weight"] * preference_score
        - w["demand_weight"] * demand_penalty
    )
    total_score = clamp(raw_total, 0.0, 100.0)

    return {
        "slot": slot,
        "is_eligible": True,
        "total_score": round(total_score, 4),
        "distance_score": round(distance_score, 4),
        "size_fit_score": round(size_fit_score, 4),
        "preference_score": round(preference_score, 4),
        "demand_penalty": round(demand_penalty, 4),
    }

def score_and_rank_slots(
    slots: List[Dict[str, Any]],
    lot: Dict[str, Any],
    vehicle: Dict[str, Any],
    preferences: Dict[str, Any],
    weights: Optional[Dict[str, float]] = None,
) -> List[Dict[str, Any]]:
    available = [s for s in slots if s.get("state") == "available"]
    scored = [score_slot(s, lot, vehicle, preferences, weights) for s in available]
    eligible = [r for r in scored if r["is_eligible"]]
    eligible.sort(key=lambda x: x["total_score"], reverse=True)
    return eligible

def evaluate_in_transit_upgrade(
    current_slot: Dict[str, Any],
    candidate_slots: List[Dict[str, Any]],
    lot: Dict[str, Any],
    vehicle: Dict[str, Any],
    preferences: Dict[str, Any],
    current_eta_minutes: float,
    weights: Optional[Dict[str, float]] = None,
) -> Tuple[bool, Optional[Dict[str, Any]], float, float]:
    """
    Evaluates dynamic in-transit upgrade (SYS-03).
    Returns (should_upgrade, best_candidate, distance_saved_m, score_diff_pts)
    """
    w = DEFAULT_WEIGHTS.copy()
    if weights:
        w.update(weights)

    if current_eta_minutes > w["upgrade_trigger_eta_minutes"]:
        return False, None, 0.0, 0.0

    current_res = score_slot(current_slot, lot, vehicle, preferences, weights)
    ranked_candidates = score_and_rank_slots(candidate_slots, lot, vehicle, preferences, weights)

    for cand in ranked_candidates:
        cand_slot = cand["slot"]
        if cand_slot.get("id") == current_slot.get("id"):
            continue

        dist_saved = float(current_slot.get("walkingDistanceMeters", 0)) - float(cand_slot.get("walkingDistanceMeters", 0))
        score_diff = cand["total_score"] - current_res["total_score"]

        if dist_saved >= w["min_improvement_meters"] and score_diff >= w["min_score_improvement_points"]:
            return True, cand_slot, dist_saved, score_diff

    return False, None, 0.0, 0.0

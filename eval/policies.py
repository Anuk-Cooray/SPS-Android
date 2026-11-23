"""
Smart Parking System (SLIIT J26-IT-335)
Policy Definitions for Baseline and Dynamic Algorithmic Strategies

Policies:
  - B0: STATIC-FCFS (Nearest compatible bay, no re-optimization, no auto-release)
  - B1: STATIC + FIXED AUTO-RELEASE (Nearest compatible bay, 15-min auto-release)
  - D1: SCORING ONLY (Multi-criteria algorithmic scoring, no upgrade, no auto-release)
  - D2: SCORING + AUTO-RELEASE (Multi-criteria scoring + 15-min auto-release, no upgrade)
  - D3: FULL DYNAMIC (Multi-criteria scoring + 15-min auto-release + in-transit upgrade)
"""

import math
from typing import Dict, Any, List, Optional, Tuple
from eval.scoring_engine import (
    score_slot,
    score_and_rank_slots,
    evaluate_in_transit_upgrade,
    is_size_compatible,
)

class BasePolicy:
    def __init__(self, name: str):
        self.name = name

    def select_initial_slot(
        self,
        slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        raise NotImplementedError

    def should_auto_release(
        self,
        reservation: Dict[str, Any],
        current_time_sec: float,
        hold_duration_sec: float = 900.0,
    ) -> bool:
        return False

    def evaluate_upgrade(
        self,
        current_slot: Dict[str, Any],
        candidate_slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
        eta_minutes: float,
        acceptance_model_override: Optional[float] = None,
        acceptance_rand: float = 0.5,
    ) -> Tuple[bool, Optional[Dict[str, Any]], float, float]:
        return False, None, 0.0, 0.0


class StaticFCFSPolicy(BasePolicy):
    """
    B0: STATIC-FCFS
    Allocates nearest compatible slot.
    No in-transit re-optimization.
    No auto-release (no-shows tie up slot for the entire scheduled session).
    """
    def __init__(self):
        super().__init__("B0_STATIC_FCFS")

    def select_initial_slot(
        self,
        slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        v_size = vehicle.get("size", "medium")
        covered_pref = preferences.get("coveredParkingOnly", False)

        available = [s for s in slots if s.get("state") == "available"]
        compatible = [s for s in available if is_size_compatible(s.get("size", "medium"), v_size)]
        if not compatible:
            return None

        # If user prefers covered, try to fulfill
        if covered_pref:
            cov = [s for s in compatible if s.get("type") == "covered"]
            if cov:
                compatible = cov

        # Nearest compatible slot (minimal walking distance)
        compatible.sort(key=lambda s: float(s.get("walkingDistanceMeters", 999.0)))
        return compatible[0]

    def should_auto_release(
        self,
        reservation: Dict[str, Any],
        current_time_sec: float,
        hold_duration_sec: float = 900.0,
    ) -> bool:
        return False


class StaticFixedAutoReleasePolicy(BasePolicy):
    """
    B1: STATIC + FIXED AUTO-RELEASE
    Allocates nearest compatible slot.
    No in-transit re-optimization.
    Auto-release triggered after 15 minutes of unarrived hold.
    """
    def __init__(self):
        super().__init__("B1_STATIC_AUTO_RELEASE")

    def select_initial_slot(
        self,
        slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        v_size = vehicle.get("size", "medium")
        covered_pref = preferences.get("coveredParkingOnly", False)

        available = [s for s in slots if s.get("state") == "available"]
        compatible = [s for s in available if is_size_compatible(s.get("size", "medium"), v_size)]
        if not compatible:
            return None

        if covered_pref:
            cov = [s for s in compatible if s.get("type") == "covered"]
            if cov:
                compatible = cov

        compatible.sort(key=lambda s: float(s.get("walkingDistanceMeters", 999.0)))
        return compatible[0]

    def should_auto_release(
        self,
        reservation: Dict[str, Any],
        current_time_sec: float,
        hold_duration_sec: float = 900.0,
    ) -> bool:
        scheduled_arrival = reservation["scheduled_arrival_sec"]
        return (current_time_sec - scheduled_arrival) >= hold_duration_sec


class ScoringOnlyPolicy(BasePolicy):
    """
    D1: SCORING ONLY
    Allocates slots using the multi-criteria algorithmic scoring engine (SYS-01).
    No in-transit upgrade.
    No auto-release.
    """
    def __init__(self):
        super().__init__("D1_SCORING_ONLY")

    def select_initial_slot(
        self,
        slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        ranked = score_and_rank_slots(slots, lot, vehicle, preferences)
        return ranked[0]["slot"] if ranked else None

    def should_auto_release(
        self,
        reservation: Dict[str, Any],
        current_time_sec: float,
        hold_duration_sec: float = 900.0,
    ) -> bool:
        return False


class ScoringAutoReleasePolicy(BasePolicy):
    """
    D2: SCORING + AUTO-RELEASE
    Allocates slots using multi-criteria scoring engine (SYS-01).
    Auto-release triggered after 15 minutes of unarrived hold (SYS-02).
    No in-transit upgrade.
    """
    def __init__(self):
        super().__init__("D2_SCORING_AUTO_RELEASE")

    def select_initial_slot(
        self,
        slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        ranked = score_and_rank_slots(slots, lot, vehicle, preferences)
        return ranked[0]["slot"] if ranked else None

    def should_auto_release(
        self,
        reservation: Dict[str, Any],
        current_time_sec: float,
        hold_duration_sec: float = 900.0,
    ) -> bool:
        scheduled_arrival = reservation["scheduled_arrival_sec"]
        return (current_time_sec - scheduled_arrival) >= hold_duration_sec


class FullDynamicPolicy(BasePolicy):
    """
    D3: FULL DYNAMIC (Our Proposed System)
    Allocates slots using multi-criteria scoring engine (SYS-01).
    Auto-releases expired holds after 15 minutes (SYS-02).
    Evaluates dynamic in-transit upgrades within ETA window (SYS-03).
    Driver upgrade acceptance is modeled via a validated logistic response curve
    or exogenous sensitivity sweep parameter.
    """
    def __init__(self, k: float = 0.04, d0: float = 25.0):
        super().__init__("D3_FULL_DYNAMIC")
        self.k = k
        self.d0 = d0

    def select_initial_slot(
        self,
        slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
    ) -> Optional[Dict[str, Any]]:
        ranked = score_and_rank_slots(slots, lot, vehicle, preferences)
        return ranked[0]["slot"] if ranked else None

    def should_auto_release(
        self,
        reservation: Dict[str, Any],
        current_time_sec: float,
        hold_duration_sec: float = 900.0,
    ) -> bool:
        scheduled_arrival = reservation["scheduled_arrival_sec"]
        return (current_time_sec - scheduled_arrival) >= hold_duration_sec

    def evaluate_upgrade(
        self,
        current_slot: Dict[str, Any],
        candidate_slots: List[Dict[str, Any]],
        lot: Dict[str, Any],
        vehicle: Dict[str, Any],
        preferences: Dict[str, Any],
        eta_minutes: float,
        acceptance_model_override: Optional[float] = None,
        acceptance_rand: float = 0.5,
    ) -> Tuple[bool, Optional[Dict[str, Any]], float, float]:
        should_upgrade, best_cand, dist_saved, score_diff = evaluate_in_transit_upgrade(
            current_slot, candidate_slots, lot, vehicle, preferences, eta_minutes
        )
        if not should_upgrade or best_cand is None:
            return False, None, 0.0, 0.0

        # Calculate acceptance probability
        # NOTE: Model assumption — not an empirical finding!
        if acceptance_model_override is not None:
            p_accept = acceptance_model_override
        else:
            # Logistic choice model: p(accept | delta_d) = 1 / (1 + exp(-k * (delta_d - d0)))
            logit_arg = -self.k * (dist_saved - self.d0)
            p_accept = 1.0 / (1.0 + math.exp(logit_arg))

        accepted = acceptance_rand < p_accept
        return accepted, best_cand, dist_saved, score_diff

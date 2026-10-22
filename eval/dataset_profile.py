"""
Smart Parking System (SLIIT J26-IT-335)
Empirical calibration profile from the Kaggle "IIoT Smart Parking Management" dataset.

Only the columns that map onto the simulator are used; everything else in the file
(sensor readings, weather, noise, payments) is ignored. Pure Python, zero external dependencies.

  Entry_Time            -> hourly arrival shape (rescaled to the config's total daily demand)
  Parking_Duration      -> empirical stay lengths in hours (0 h rows become the 0.5 h minimum)
  Vehicle_Type + Weight -> vehicle size mix (Motorcycle = small, >= 2000 kg = large, else medium)
  Spot_Size             -> bay size mix (Compact = small, Standard = medium, Oversized = large)
"""

import csv
from collections import Counter
from pathlib import Path
from typing import Any, Dict

LARGE_VEHICLE_KG = 2000.0
SPOT_SIZE_MAP = {"Compact": "small", "Standard": "medium", "Oversized": "large"}


def _vehicle_size(row: Dict[str, str]) -> str:
    if row["Vehicle_Type"] == "Motorcycle":
        return "small"
    return "large" if float(row["Vehicle_Type_Weight"]) >= LARGE_VEHICLE_KG else "medium"


def build_profile(csv_path: Path, config: Dict[str, Any]) -> Dict[str, Any]:
    with open(csv_path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    n = len(rows)

    # Hourly shape, rescaled so the day's expected arrivals match the baseline config
    entry_counts = Counter(int(r["Entry_Time"]) for r in rows)
    raw_shape = [entry_counts.get(h, 0) / n for h in range(24)]
    baseline_total = sum(config["demand"]["hourly_profile"])
    hourly_profile = [round(s * baseline_total, 4) for s in raw_shape]

    durations = sorted(float(r["Parking_Duration"]) for r in rows)

    v_counts = Counter(_vehicle_size(r) for r in rows)
    small_share = v_counts["small"] / n
    medium_share = v_counts["medium"] / n

    # Bay sizes for the same 72-bay lot, rounded so they still add up to the total
    total_slots = config["facility"]["total_slots"]
    s_counts = Counter(SPOT_SIZE_MAP[r["Spot_Size"]] for r in rows)
    small_bays = round(total_slots * s_counts["small"] / n)
    large_bays = round(total_slots * s_counts["large"] / n)
    slot_sizes = {"small": small_bays, "medium": total_slots - small_bays - large_bays, "large": large_bays}

    return {
        "source": Path(csv_path).name,
        "rows": n,
        "hourly_profile": hourly_profile,
        "duration_hours": durations,
        "duration_mean_hours": round(sum(max(0.5, d) for d in durations) / n, 3),
        "vehicle_cutoffs": (small_share, small_share + medium_share),
        "vehicle_mix_pct": {k: round(100 * v_counts[k] / n, 1) for k in ("small", "medium", "large")},
        "slot_sizes": slot_sizes,
    }

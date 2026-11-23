"""
Smart Parking System (SLIIT J26-IT-335)
Dataset-Calibrated Evaluation Runner

Re-runs the 30-seed, 5-policy comparison twice on identical seeds:
  1. BASELINE   - the assumption-driven config.yaml profile (same as run_eval.py)
  2. CALIBRATED - arrival shape, stay lengths, vehicle mix and bay mix taken from the
                  Kaggle IIoT Smart Parking Management dataset (eval/dataset_profile.py)
Total daily demand is held equal so the two scenarios differ only in the calibrated inputs.

The CSV is not committed: download "IIoT Smart Parking Management" from Kaggle into eval/data/.

Usage (from the project root):
  python -m eval.run_dataset_eval [path/to/IIoT_Smart_Parking_Management.csv]
"""

import copy
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

from eval.config_loader import load_config
from eval.dataset_profile import build_profile
from eval.policies import (
    StaticFCFSPolicy,
    StaticFixedAutoReleasePolicy,
    ScoringOnlyPolicy,
    ScoringAutoReleasePolicy,
    FullDynamicPolicy,
)
from eval.simulation_engine import generate_trip_stream, run_simulation
from eval.statistics import confidence_interval_95, wilcoxon_signed_rank_test

KPIS = [
    "lot_utilisation_pct",
    "rejection_rate_pct",
    "mean_walking_distance_m",
    "slot_minutes_recovered",
    "walking_distance_saved_mean_m",
    "upgrade_acceptance_pct",
]


def run_scenario(config: Dict[str, Any], seeds: List[int], profile=None) -> Dict[str, List[Dict[str, Any]]]:
    policies = [
        StaticFCFSPolicy(),
        StaticFixedAutoReleasePolicy(),
        ScoringOnlyPolicy(),
        ScoringAutoReleasePolicy(),
        FullDynamicPolicy(),
    ]
    raw: Dict[str, List[Dict[str, Any]]] = {p.name: [] for p in policies}
    for s in seeds:
        trips = generate_trip_stream(seed=s, config=config, profile=profile)
        for p in policies:
            res = run_simulation(policy=p, trips=trips, config=config)
            res["seed"] = s
            raw[p.name].append(res)
    return raw


def summarise(raw: Dict[str, List[Dict[str, Any]]]) -> Dict[str, Any]:
    summary: Dict[str, Any] = {}
    for policy, runs in raw.items():
        summary[policy] = {}
        for kpi in KPIS:
            m, margin, _ = confidence_interval_95([r[kpi] for r in runs])
            summary[policy][kpi] = {"mean": round(m, 3), "ci_margin_95": round(margin, 3)}
    tests: Dict[str, Any] = {}
    for baseline in ["B0_STATIC_FCFS", "B1_STATIC_AUTO_RELEASE"]:
        tests[f"D3_FULL_DYNAMIC_vs_{baseline}"] = {
            kpi: wilcoxon_signed_rank_test(
                [r[kpi] for r in raw["D3_FULL_DYNAMIC"]],
                [r[kpi] for r in raw[baseline]],
            )
            for kpi in KPIS
        }
    return {"kpis": summary, "wilcoxon": tests}


def main():
    base_dir = Path(__file__).parent
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else base_dir / "data" / "IIoT_Smart_Parking_Management.csv"
    out_dir = base_dir / "results" / "dataset_calibrated"
    out_dir.mkdir(parents=True, exist_ok=True)

    config = load_config(base_dir / "config.yaml")
    seeds_count = config["simulation"].get("seeds_count", 30)
    base_seed = config["simulation"].get("base_seed", 20261019)
    seeds = [base_seed + i for i in range(seeds_count)]

    profile = build_profile(csv_path, config)
    calibrated_config = copy.deepcopy(config)
    calibrated_config["facility"]["slot_sizes"] = profile["slot_sizes"]

    print(f"[{datetime.now().strftime('%H:%M:%S')}] Profile from {profile['source']} ({profile['rows']} rows)")
    print(f"  vehicle mix %: {profile['vehicle_mix_pct']} | bay mix: {profile['slot_sizes']} | mean stay: {profile['duration_mean_hours']} h")

    results = {}
    for name, cfg, prof in (("baseline", config, None), ("calibrated", calibrated_config, profile)):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Running {name}: {len(seeds)} seeds x 5 policies...")
        raw = run_scenario(cfg, seeds, prof)
        results[name] = summarise(raw)
        with open(out_dir / f"raw_{name}.csv", "w", newline="", encoding="utf-8") as f:
            fields = ["seed", "policy"] + KPIS + ["total_requests", "rejections", "upgrades_offered", "upgrades_accepted"]
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            for runs in raw.values():
                for r in runs:
                    w.writerow({k: r.get(k, 0) for k in fields})

    with open(out_dir / "summary.json", "w", encoding="utf-8") as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "seeds": seeds,
            "profile": {k: v for k, v in profile.items() if k != "duration_hours"},
            "baseline_hourly_profile": config["demand"]["hourly_profile"],
            "results": results,
            "notes": "Dataset is synthetic (Kaggle); used only for distributions that map onto the simulator.",
        }, f, indent=2)

    print(f"\n{'Policy':<26}{'Util % (base/cal)':>22}{'Reject % (base/cal)':>24}{'Walk m (base/cal)':>22}")
    for policy in results["baseline"]["kpis"]:
        b, c = results["baseline"]["kpis"][policy], results["calibrated"]["kpis"][policy]
        print(f"{policy:<26}"
              f"{b['lot_utilisation_pct']['mean']:>11.1f} /{c['lot_utilisation_pct']['mean']:>6.1f}   "
              f"{b['rejection_rate_pct']['mean']:>12.1f} /{c['rejection_rate_pct']['mean']:>6.1f}   "
              f"{b['mean_walking_distance_m']['mean']:>11.1f} /{c['mean_walking_distance_m']['mean']:>6.1f}")
    print(f"Saved to {out_dir}")


if __name__ == "__main__":
    main()

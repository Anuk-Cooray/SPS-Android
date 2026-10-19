"""
Smart Parking System (SLIIT J26-IT-335)
Reproducibility Evaluation Runner

Executes 30 stochastic seeds across 5 policies (B0, B1, D1, D2, D3),
parameter sweeps (demand, no-shows, traffic delay, upgrade acceptance),
computes 95% Confidence Intervals and paired Wilcoxon signed-rank tests,
and saves results with full audit metadata.
"""

import os
import sys
import csv
import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List

from eval.config_loader import load_config
from eval.policies import (
    StaticFCFSPolicy,
    StaticFixedAutoReleasePolicy,
    ScoringOnlyPolicy,
    ScoringAutoReleasePolicy,
    FullDynamicPolicy,
)
from eval.simulation_engine import generate_trip_stream, run_simulation
from eval.statistics import (
    mean,
    std_dev,
    confidence_interval_95,
    wilcoxon_signed_rank_test,
)

def get_git_commit_hash() -> str:
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout.strip()
    except Exception:
        return "unknown"

def main():
    base_dir = Path(__file__).parent
    config_path = base_dir / "config.yaml"
    results_dir = base_dir / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{datetime.now().strftime('%H:%M:%S')}] Loading evaluation configuration...")
    config = load_config(config_path)

    seeds_count = config["simulation"].get("seeds_count", 30)
    base_seed = config["simulation"].get("base_seed", 20261019)
    seeds = [base_seed + i for i in range(seeds_count)]

    commit_hash = get_git_commit_hash()
    print(f"Git commit: {commit_hash} | Seeds: {len(seeds)} (base: {base_seed})")

    policies = [
        StaticFCFSPolicy(),
        StaticFixedAutoReleasePolicy(),
        ScoringOnlyPolicy(),
        ScoringAutoReleasePolicy(),
        FullDynamicPolicy(),
    ]

    # Metrics to track
    kpis = [
        "walking_distance_saved_mean_m",
        "slot_minutes_recovered",
        "lot_utilisation_pct",
        "turnover_at_peak",
        "rejection_rate_pct",
        "mean_walking_distance_m",
        "upgrade_acceptance_pct",
    ]

    print(f"\n--- Running 30-Seed Main Comparison (B0, B1, D1, D2, D3) ---")
    raw_results: Dict[str, List[Dict[str, Any]]] = {p.name: [] for p in policies}

    for seed_idx, s in enumerate(seeds):
        # Generate trip stream once for this seed — synchronized across all 5 policies!
        trips = generate_trip_stream(seed=s, config=config)

        for p in policies:
            res = run_simulation(policy=p, trips=trips, config=config)
            res["seed"] = s
            raw_results[p.name].append(res)

        if (seed_idx + 1) % 5 == 0 or seed_idx == seeds_count - 1:
            print(f"  Processed seed {seed_idx + 1}/{seeds_count}...")

    # Save raw seed data
    raw_csv_path = results_dir / "raw_seeds_data.csv"
    with open(raw_csv_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = ["seed", "policy"] + kpis + ["total_requests", "completed_parkings", "rejections", "upgrades_offered", "upgrades_accepted"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for p in policies:
            for row in raw_results[p.name]:
                writer.writerow({k: row.get(k, 0) for k in fieldnames})
    print(f"Saved raw seed data to {raw_csv_path}")

    # Compute Statistical Summary (Mean, Std, 95% CI)
    stats_summary: Dict[str, Dict[str, Any]] = {}
    for p in policies:
        p_name = p.name
        stats_summary[p_name] = {}
        for kpi in kpis:
            vals = [r[kpi] for r in raw_results[p_name]]
            m, margin, (ci_low, ci_high) = confidence_interval_95(vals)
            s_d = std_dev(vals)
            stats_summary[p_name][kpi] = {
                "mean": round(m, 3),
                "std": round(s_d, 3),
                "ci_margin_95": round(margin, 3),
                "ci_95_low": round(ci_low, 3),
                "ci_95_high": round(ci_high, 3),
            }

    # Hypothesis Testing: Paired Wilcoxon Signed-Rank Tests (D3 vs B0, D3 vs B1)
    wilcoxon_tests: Dict[str, Dict[str, Any]] = {}
    for baseline in ["B0_STATIC_FCFS", "B1_STATIC_AUTO_RELEASE"]:
        comp_key = f"D3_FULL_DYNAMIC_vs_{baseline}"
        wilcoxon_tests[comp_key] = {}
        for kpi in kpis:
            d3_vals = [r[kpi] for r in raw_results["D3_FULL_DYNAMIC"]]
            base_vals = [r[kpi] for r in raw_results[baseline]]
            test_res = wilcoxon_signed_rank_test(d3_vals, base_vals)
            wilcoxon_tests[comp_key][kpi] = test_res

    # Save stats_summary.csv
    summary_csv_path = results_dir / "stats_summary.csv"
    with open(summary_csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Policy", "KPI", "Mean", "StdDev", "95% CI Half-Width", "95% CI Lower", "95% CI Upper"])
        for p in policies:
            for kpi in kpis:
                st = stats_summary[p.name][kpi]
                writer.writerow([
                    p.name,
                    kpi,
                    st["mean"],
                    st["std"],
                    st["ci_margin_95"],
                    st["ci_95_low"],
                    st["ci_95_high"],
                ])

        writer.writerow([])
        writer.writerow(["Hypothesis Test", "KPI", "W Statistic", "z-score", "p-value", "p < 0.05", "p < 0.01"])
        for comp_key, tests in wilcoxon_tests.items():
            for kpi, t in tests.items():
                writer.writerow([
                    comp_key,
                    kpi,
                    t["statistic_W"],
                    t["z_score"],
                    t["p_value"],
                    t["significant_at_05"],
                    t["significant_at_01"],
                ])
    print(f"Saved statistical summary to {summary_csv_path}")

    # --- Parameter Sweeps ---
    print(f"\n--- Running Sensitivity Sweeps ---")
    sweep_results: Dict[str, Any] = {}

    # 1. Demand Sweep (30, 50, 75, 100 drivers/h)
    print("1. Running Demand Sweep...")
    demand_vals = config["demand"].get("demand_sweep", [30, 50, 75, 100])
    sweep_results["demand_sweep"] = []
    for d in demand_vals:
        sweep_entry = {"demand_per_hour": d, "policies": {}}
        for p in [StaticFCFSPolicy(), StaticFixedAutoReleasePolicy(), FullDynamicPolicy()]:
            kpi_accum = {k: [] for k in kpis}
            for s in seeds[:15]:  # 15 seeds for sweep speed
                trips = generate_trip_stream(seed=s, config=config, demand_per_hour_override=d)
                sim_res = run_simulation(policy=p, trips=trips, config=config)
                for k in kpis:
                    kpi_accum[k].append(sim_res[k])
            sweep_entry["policies"][p.name] = {
                k: round(mean(kpi_accum[k]), 2) for k in kpis
            }
        sweep_results["demand_sweep"].append(sweep_entry)

    # 2. No-Show Sweep (5%, 10%, 15%, 20%)
    print("2. Running No-Show Sweep...")
    ns_vals = config["stochastic_driver"].get("no_show_sweep", [0.05, 0.10, 0.15, 0.20])
    sweep_results["no_show_sweep"] = []
    for ns in ns_vals:
        sweep_entry = {"no_show_rate": ns, "policies": {}}
        for p in [StaticFCFSPolicy(), StaticFixedAutoReleasePolicy(), FullDynamicPolicy()]:
            kpi_accum = {k: [] for k in kpis}
            for s in seeds[:15]:
                trips = generate_trip_stream(seed=s, config=config, no_show_rate_override=ns)
                sim_res = run_simulation(policy=p, trips=trips, config=config)
                for k in kpis:
                    kpi_accum[k].append(sim_res[k])
            sweep_entry["policies"][p.name] = {
                k: round(mean(kpi_accum[k]), 2) for k in kpis
            }
        sweep_results["no_show_sweep"].append(sweep_entry)

    # 3. Delay Sweep (0, 3, 5, 10 min)
    print("3. Running Delay Sweep...")
    delay_vals = config["stochastic_driver"].get("delay_sweep", [0.0, 3.0, 5.0, 10.0])
    sweep_results["delay_sweep"] = []
    for del_m in delay_vals:
        sweep_entry = {"mean_delay_min": del_m, "policies": {}}
        for p in [StaticFCFSPolicy(), StaticFixedAutoReleasePolicy(), FullDynamicPolicy()]:
            kpi_accum = {k: [] for k in kpis}
            for s in seeds[:15]:
                trips = generate_trip_stream(seed=s, config=config, mean_delay_override=del_m)
                sim_res = run_simulation(policy=p, trips=trips, config=config)
                for k in kpis:
                    kpi_accum[k].append(sim_res[k])
            sweep_entry["policies"][p.name] = {
                k: round(mean(kpi_accum[k]), 2) for k in kpis
            }
        sweep_results["delay_sweep"].append(sweep_entry)

    # 4. Upgrade Acceptance Sensitivity Sweep (p in {0.3, 0.5, 0.7, 0.9})
    print("4. Running Upgrade Acceptance Sensitivity Sweep...")
    acc_vals = config["acceptance_model"].get("fixed_sweep", [0.30, 0.50, 0.70, 0.90])
    sweep_results["acceptance_sweep"] = []
    d3_policy = FullDynamicPolicy()
    for acc in acc_vals:
        sweep_entry = {"acceptance_probability_assumption": acc, "results": {}}
        kpi_accum = {k: [] for k in kpis}
        for s in seeds[:15]:
            trips = generate_trip_stream(seed=s, config=config)
            sim_res = run_simulation(
                policy=d3_policy,
                trips=trips,
                config=config,
                acceptance_model_override=acc,
            )
            for k in kpis:
                kpi_accum[k].append(sim_res[k])
        sweep_entry["results"] = {k: round(mean(kpi_accum[k]), 2) for k in kpis}
        sweep_results["acceptance_sweep"].append(sweep_entry)

    # Save sensitivity sweeps json
    sweeps_path = results_dir / "sensitivity_sweeps.json"
    with open(sweeps_path, "w", encoding="utf-8") as f:
        json.dump(sweep_results, f, indent=2)
    print(f"Saved sensitivity sweeps to {sweeps_path}")

    # Save metadata.json
    metadata = {
        "timestamp": datetime.now().isoformat(),
        "git_commit_hash": commit_hash,
        "seeds_count": seeds_count,
        "base_seed": base_seed,
        "seeds": seeds,
        "config": config,
        "policies_evaluated": [p.name for p in policies],
        "kpis": kpis,
        "notes": {
            "upgrade_acceptance": "Upgrade acceptance is an exogenous behavioral input model, NOT an empirical finding.",
            "latency": "Algorithmic latency is measured via real Dart and TypeScript runtime benchmarks, NOT Python simulation execution.",
        },
    }
    meta_path = results_dir / "metadata.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)
    print(f"Saved run metadata to {meta_path}")

    print("\n--- Evaluation Complete ---")

if __name__ == "__main__":
    main()

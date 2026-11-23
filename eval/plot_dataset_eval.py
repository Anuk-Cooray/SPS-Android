"""
Smart Parking System (SLIIT J26-IT-335)
Charts for the dataset-calibrated evaluation (reads results/dataset_calibrated/summary.json).

Usage (from the project root, after run_dataset_eval):
  python -m eval.plot_dataset_eval
"""

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

INK = "#0A0A0A"
GRAY = "#66666F"
LINE = "#D4D4D8"
BASE = "#A1A1AA"
CAL = "#2563EB"
POLICIES = [("B0_STATIC_FCFS", "B0 static"), ("B1_STATIC_AUTO_RELEASE", "B1 + release"), ("D3_FULL_DYNAMIC", "D3 full dynamic")]
PANELS = [
    ("lot_utilisation_pct", "Lot utilisation (%)"),
    ("rejection_rate_pct", "Rejection rate (%)"),
    ("mean_walking_distance_m", "Mean walking distance (m)"),
]

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.edgecolor": LINE,
                     "axes.labelcolor": GRAY, "xtick.color": GRAY, "ytick.color": GRAY})


def style(ax):
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.grid(axis="y", color=LINE, linewidth=0.6)
    ax.set_axisbelow(True)


def main():
    out_dir = Path(__file__).parent / "results" / "dataset_calibrated"
    data = json.loads((out_dir / "summary.json").read_text(encoding="utf-8"))
    charts = out_dir / "charts"
    charts.mkdir(exist_ok=True)
    demand = 60

    # 1. Arrival profile: assumed diurnal curve vs the dataset's entry-hour distribution
    fig, ax = plt.subplots(figsize=(8.6, 3.4), dpi=200)
    hours = list(range(24))
    ax.plot(hours, [m * demand for m in data["baseline_hourly_profile"]], color=BASE, linewidth=2.2, marker="o", markersize=3.5, label="Baseline assumption (config.yaml)")
    ax.plot(hours, [m * demand for m in data["profile"]["hourly_profile"]], color=CAL, linewidth=2.2, marker="o", markersize=3.5, label="Calibrated from Kaggle dataset")
    ax.set_xticks(range(0, 24, 2))
    ax.set_xlabel("Hour of day")
    ax.set_ylabel("Expected arrivals / hour")
    ax.legend(frameon=False, loc="lower center", bbox_to_anchor=(0.5, 1.0), ncol=2)
    style(ax)
    fig.tight_layout()
    fig.savefig(charts / "arrival_profile.png")
    plt.close(fig)

    # 2. KPI comparison per policy, both scenarios, mean +/- 95% CI
    fig, axes = plt.subplots(1, 3, figsize=(10.5, 3.6), dpi=200)
    width = 0.36
    for ax, (kpi, title) in zip(axes, PANELS):
        for i, (scenario, color, label) in enumerate((("baseline", BASE, "Baseline"), ("calibrated", CAL, "Dataset-calibrated"))):
            stats = [data["results"][scenario]["kpis"][p][kpi] for p, _ in POLICIES]
            xs = [x + (i - 0.5) * width for x in range(len(POLICIES))]
            ax.bar(xs, [s["mean"] for s in stats], width, yerr=[s["ci_margin_95"] for s in stats],
                   color=color, label=label, capsize=3, error_kw={"ecolor": INK, "elinewidth": 0.8})
        ax.set_xticks(range(len(POLICIES)))
        ax.set_xticklabels([short for _, short in POLICIES], fontsize=8.5)
        ax.set_title(title, fontsize=10, color=INK)
        lo = min(data["results"][s]["kpis"][p][kpi]["mean"] for s in ("baseline", "calibrated") for p, _ in POLICIES)
        ax.set_ylim(lo * 0.85 if kpi == "mean_walking_distance_m" else 0, None)
        style(ax)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, frameon=False, loc="lower center", ncol=2, fontsize=9)
    fig.tight_layout(rect=(0, 0.07, 1, 1))
    fig.savefig(charts / "kpi_comparison.png")
    plt.close(fig)
    print(f"Saved charts to {charts}")


if __name__ == "__main__":
    main()

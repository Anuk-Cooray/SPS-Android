"""
Smart Parking System (SLIIT J26-IT-335)
Reproducibility Chart Generation Script (Pure Python SVG & HTML)

Generates publication-quality vector SVG charts with 95% Confidence Interval error bars
for all 6 KPIs across policies (B0, B1, D1, D2, D3), plus sensitivity sweep curves.
Zero external dependencies required.
"""

import csv
import json
from pathlib import Path
from typing import Dict, Any, List

def create_bar_chart_with_error_bars(
    title: str,
    subtitle: str,
    y_label: str,
    categories: List[str],
    means: List[float],
    ci_margins: List[float],
    output_path: Path,
    unit: str = "",
):
    width = 750
    height = 420
    margin_top = 70
    margin_bottom = 60
    margin_left = 90
    margin_right = 40

    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    # Find max y
    max_val = max(m + c for m, c in zip(means, ci_margins)) if means else 10.0
    if max_val <= 0:
        max_val = 1.0
    y_max = max_val * 1.25

    n_bars = len(categories)
    slot_w = plot_w / n_bars
    bar_w = min(65.0, slot_w * 0.55)

    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%" style="background:#0F172A; font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;">')

    # Gridlines and y-ticks
    n_ticks = 5
    for i in range(n_ticks + 1):
        v = (y_max / n_ticks) * i
        y_pos = margin_top + plot_h - (v / y_max) * plot_h
        svg.append(f'  <line x1="{margin_left}" y1="{y_pos:.1f}" x2="{width - margin_right}" y2="{y_pos:.1f}" stroke="#334155" stroke-dasharray="4,4" stroke-width="1"/>')
        val_str = f"{v:.1f}" if y_max < 10 else f"{int(v)}"
        svg.append(f'  <text x="{margin_left - 12}" y="{y_pos + 4:.1f}" fill="#94A3B8" font-size="12" text-anchor="end">{val_str}{unit}</text>')

    # Title & Subtitle
    svg.append(f'  <text x="{margin_left}" y="32" fill="#F8FAFC" font-size="16" font-weight="bold">{title}</text>')
    svg.append(f'  <text x="{margin_left}" y="52" fill="#94A3B8" font-size="12">{subtitle}</text>')

    # Y-axis label
    svg.append(f'  <text x="{- (margin_top + plot_h / 2)}" y="25" fill="#94A3B8" font-size="12" font-weight="500" text-anchor="middle" transform="rotate(-90)">{y_label}</text>')

    # Axes
    svg.append(f'  <line x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{margin_top + plot_h}" stroke="#64748B" stroke-width="1.5"/>')
    svg.append(f'  <line x1="{margin_left}" y1="{margin_top + plot_h}" x2="{width - margin_right}" y2="{margin_top + plot_h}" stroke="#64748B" stroke-width="1.5"/>')

    # Bars & Error Bars
    palette = {
        "B0": "#64748B",  # Neutral grey
        "B1": "#94A3B8",  # Light grey
        "D1": "#38BDF8",  # Sky blue
        "D2": "#60A5FA",  # Medium blue
        "D3": "#2563EB",  # Primary Accent Blue (Ours)
    }

    for idx, (cat, m, c) in enumerate(zip(categories, means, ci_margins)):
        cx = margin_left + idx * slot_w + slot_w / 2
        bx = cx - bar_w / 2
        bar_h = (m / y_max) * plot_h
        by = margin_top + plot_h - bar_h

        color_key = cat.split("_")[0] if "_" in cat else cat[:2]
        color = palette.get(color_key, "#2563EB")

        # Bar
        svg.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bar_w:.1f}" height="{bar_h:.1f}" rx="4" fill="{color}" opacity="0.9"/>')

        # Error bar
        y_top = margin_top + plot_h - ((m + c) / y_max) * plot_h
        y_bot = margin_top + plot_h - (max(0.0, m - c) / y_max) * plot_h
        eb_cap = 10.0
        svg.append(f'  <line x1="{cx:.1f}" y1="{y_bot:.1f}" x2="{cx:.1f}" y2="{y_top:.1f}" stroke="#F8FAFC" stroke-width="2"/>')
        svg.append(f'  <line x1="{cx - eb_cap:.1f}" y1="{y_top:.1f}" x2="{cx + eb_cap:.1f}" y2="{y_top:.1f}" stroke="#F8FAFC" stroke-width="2"/>')
        svg.append(f'  <line x1="{cx - eb_cap:.1f}" y1="{y_bot:.1f}" x2="{cx + eb_cap:.1f}" y2="{y_bot:.1f}" stroke="#F8FAFC" stroke-width="2"/>')

        # Value label
        val_display = f"{m:.1f}" if m < 100 else f"{int(m)}"
        svg.append(f'  <text x="{cx:.1f}" y="{by - 12:.1f}" fill="#F8FAFC" font-size="12" font-weight="bold" text-anchor="middle">{val_display}</text>')

        # X label
        short_cat = cat.replace("_", "\n").split("\n")[0]
        svg.append(f'  <text x="{cx:.1f}" y="{margin_top + plot_h + 24}" fill="#CBD5E1" font-size="12" font-weight="600" text-anchor="middle">{short_cat}</text>')
        desc_label = cat[len(short_cat) + 1:] if len(cat) > len(short_cat) else ""
        if desc_label:
            desc_sub = desc_label.replace("_", " ").title()[:12]
            svg.append(f'  <text x="{cx:.1f}" y="{margin_top + plot_h + 40}" fill="#64748B" font-size="10" text-anchor="middle">{desc_sub}</text>')

    svg.append('</svg>')

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))


def create_sensitivity_line_chart(
    title: str,
    subtitle: str,
    x_label: str,
    y_label: str,
    x_vals: List[float],
    series_data: Dict[str, List[float]],
    output_path: Path,
):
    width = 750
    height = 420
    margin_top = 70
    margin_bottom = 60
    margin_left = 90
    margin_right = 160

    plot_w = width - margin_left - margin_right
    plot_h = height - margin_top - margin_bottom

    all_y = [v for vals in series_data.values() for v in vals]
    y_min = 0.0
    y_max = max(all_y) * 1.25 if all_y else 10.0

    x_min = min(x_vals) if x_vals else 0.0
    x_max = max(x_vals) if x_vals else 10.0
    x_range = x_max - x_min if x_max > x_min else 1.0

    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="100%" height="100%" style="background:#0F172A; font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;">')

    # Gridlines
    n_ticks = 5
    for i in range(n_ticks + 1):
        v = (y_max / n_ticks) * i
        y_pos = margin_top + plot_h - (v / y_max) * plot_h
        svg.append(f'  <line x1="{margin_left}" y1="{y_pos:.1f}" x2="{margin_left + plot_w}" y2="{y_pos:.1f}" stroke="#334155" stroke-dasharray="4,4" stroke-width="1"/>')
        val_str = f"{v:.1f}" if y_max < 10 else f"{int(v)}"
        svg.append(f'  <text x="{margin_left - 12}" y="{y_pos + 4:.1f}" fill="#94A3B8" font-size="12" text-anchor="end">{val_str}</text>')

    for x in x_vals:
        x_pos = margin_left + ((x - x_min) / x_range) * plot_w
        svg.append(f'  <line x1="{x_pos:.1f}" y1="{margin_top}" x2="{x_pos:.1f}" y2="{margin_top + plot_h}" stroke="#1E293B" stroke-width="1"/>')
        x_str = f"{x:g}"
        svg.append(f'  <text x="{x_pos:.1f}" y="{margin_top + plot_h + 24}" fill="#94A3B8" font-size="12" text-anchor="middle">{x_str}</text>')

    # Title & Subtitle
    svg.append(f'  <text x="{margin_left}" y="32" fill="#F8FAFC" font-size="16" font-weight="bold">{title}</text>')
    svg.append(f'  <text x="{margin_left}" y="52" fill="#94A3B8" font-size="12">{subtitle}</text>')

    # Axis Labels
    svg.append(f'  <text x="{margin_left + plot_w / 2}" y="{height - 12}" fill="#CBD5E1" font-size="12" font-weight="500" text-anchor="middle">{x_label}</text>')
    svg.append(f'  <text x="{- (margin_top + plot_h / 2)}" y="25" fill="#94A3B8" font-size="12" font-weight="500" text-anchor="middle" transform="rotate(-90)">{y_label}</text>')

    # Axes
    svg.append(f'  <line x1="{margin_left}" y1="{margin_top}" x2="{margin_left}" y2="{margin_top + plot_h}" stroke="#64748B" stroke-width="1.5"/>')
    svg.append(f'  <line x1="{margin_left}" y1="{margin_top + plot_h}" x2="{margin_left + plot_w}" y2="{margin_top + plot_h}" stroke="#64748B" stroke-width="1.5"/>')

    palette = ["#64748B", "#94A3B8", "#38BDF8", "#2563EB"]
    legend_y = margin_top + 10

    for s_idx, (s_name, y_pts) in enumerate(series_data.items()):
        color = palette[s_idx % len(palette)]
        coords = []
        for x, y in zip(x_vals, y_pts):
            px = margin_left + ((x - x_min) / x_range) * plot_w
            py = margin_top + plot_h - (y / y_max) * plot_h
            coords.append((px, py))

        # Polyline
        pts_str = " ".join(f"{px:.1f},{py:.1f}" for px, py in coords)
        svg.append(f'  <polyline fill="none" stroke="{color}" stroke-width="2.5" points="{pts_str}"/>')

        # Data markers
        for px, py in coords:
            svg.append(f'  <circle cx="{px:.1f}" cy="{py:.1f}" r="4" fill="{color}" stroke="#0F172A" stroke-width="2"/>')

        # Legend entry
        leg_x = margin_left + plot_w + 20
        svg.append(f'  <line x1="{leg_x}" y1="{legend_y + s_idx * 24}" x2="{leg_x + 18}" y2="{legend_y + s_idx * 24}" stroke="{color}" stroke-width="2.5"/>')
        svg.append(f'  <circle cx="{leg_x + 9}" cy="{legend_y + s_idx * 24}" r="3.5" fill="{color}"/>')
        label_short = s_name.split("_")[0] + " " + s_name.split("_")[1] if "_" in s_name else s_name
        svg.append(f'  <text x="{leg_x + 26}" y="{legend_y + s_idx * 24 + 4}" fill="#CBD5E1" font-size="11">{label_short}</text>')

    svg.append('</svg>')

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))


def generate_all_charts():
    base_dir = Path(__file__).parent
    results_dir = base_dir / "results"
    charts_dir = results_dir / "charts"
    charts_dir.mkdir(parents=True, exist_ok=True)

    summary_csv = results_dir / "stats_summary.csv"
    if not summary_csv.exists():
        print(f"Error: {summary_csv} does not exist yet. Run eval/run_eval.py first.")
        return

    # Parse stats_summary.csv
    policy_kpi_stats: Dict[str, Dict[str, Dict[str, float]]] = {}
    with open(summary_csv, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            if not row or row[0].startswith("Hypothesis Test"):
                break
            if len(row) >= 7:
                p, kpi, m, s, margin, low, high = row[0], row[1], float(row[2]), float(row[3]), float(row[4]), float(row[5]), float(row[6])
                if p not in policy_kpi_stats:
                    policy_kpi_stats[p] = {}
                policy_kpi_stats[p][kpi] = {"mean": m, "margin": margin, "std": s}

    policies = ["B0_STATIC_FCFS", "B1_STATIC_AUTO_RELEASE", "D1_SCORING_ONLY", "D2_SCORING_AUTO_RELEASE", "D3_FULL_DYNAMIC"]

    # 1. Walking distance saved
    means = [policy_kpi_stats[p]["walking_distance_saved_mean_m"]["mean"] for p in policies]
    margins = [policy_kpi_stats[p]["walking_distance_saved_mean_m"]["margin"] for p in policies]
    create_bar_chart_with_error_bars(
        title="Walking Distance Saved per Driver (Metres)",
        subtitle="Comparison across baseline and dynamic strategies (Mean ± 95% Confidence Interval, N=30)",
        y_label="Metres Saved (m)",
        categories=policies,
        means=means,
        ci_margins=margins,
        output_path=charts_dir / "kpi1_walking_distance_saved.svg",
        unit="m",
    )

    # 2. Slot-minutes recovered
    means = [policy_kpi_stats[p]["slot_minutes_recovered"]["mean"] for p in policies]
    margins = [policy_kpi_stats[p]["slot_minutes_recovered"]["margin"] for p in policies]
    create_bar_chart_with_error_bars(
        title="Total Slot-Minutes Recovered from No-Shows & Expired Holds",
        subtitle="Quantifies reclaimed bay capacity over 24h diurnal cycle (Mean ± 95% CI, N=30)",
        y_label="Recovered Minutes (min)",
        categories=policies,
        means=means,
        ci_margins=margins,
        output_path=charts_dir / "kpi2_slot_minutes_recovered.svg",
        unit="m",
    )

    # 3. Lot utilisation
    means = [policy_kpi_stats[p]["lot_utilisation_pct"]["mean"] for p in policies]
    margins = [policy_kpi_stats[p]["lot_utilisation_pct"]["margin"] for p in policies]
    create_bar_chart_with_error_bars(
        title="Average Facility Utilization Rate (%)",
        subtitle="24-hour time-weighted slot occupancy (Mean ± 95% CI, N=30)",
        y_label="Utilization (%)",
        categories=policies,
        means=means,
        ci_margins=margins,
        output_path=charts_dir / "kpi3_lot_utilisation.svg",
        unit="%",
    )

    # 4. Turnover at peak
    means = [policy_kpi_stats[p]["turnover_at_peak"]["mean"] for p in policies]
    margins = [policy_kpi_stats[p]["turnover_at_peak"]["margin"] for p in policies]
    create_bar_chart_with_error_bars(
        title="Peak-Hour Bay Turnover (Vehicles / Bay)",
        subtitle="Turnover during morning (08:00-10:00) & evening (16:00-18:00) peak (Mean ± 95% CI, N=30)",
        y_label="Parked Vehicles per Bay",
        categories=policies,
        means=means,
        ci_margins=margins,
        output_path=charts_dir / "kpi4_peak_turnover.svg",
    )

    # 5. Rejection Rate
    means = [policy_kpi_stats[p]["rejection_rate_pct"]["mean"] for p in policies]
    margins = [policy_kpi_stats[p]["rejection_rate_pct"]["margin"] for p in policies]
    create_bar_chart_with_error_bars(
        title="System Reservation Rejection Rate (%)",
        subtitle="Percentage of incoming requests rejected due to lack of compatible bays (Mean ± 95% CI)",
        y_label="Rejections (%)",
        categories=policies,
        means=means,
        ci_margins=margins,
        output_path=charts_dir / "kpi5_rejection_rate.svg",
        unit="%",
    )

    # 6. Mean walking distance
    means = [policy_kpi_stats[p]["mean_walking_distance_m"]["mean"] for p in policies]
    margins = [policy_kpi_stats[p]["mean_walking_distance_m"]["margin"] for p in policies]
    create_bar_chart_with_error_bars(
        title="Mean Driver Walking Distance to Facility Entrance (Metres)",
        subtitle="Lower is better: measures driver convenience and spatial compactness (Mean ± 95% CI)",
        y_label="Walking Distance (m)",
        categories=policies,
        means=means,
        ci_margins=margins,
        output_path=charts_dir / "kpi6_mean_walking_distance.svg",
        unit="m",
    )

    # Load sensitivity sweeps
    sweeps_path = results_dir / "sensitivity_sweeps.json"
    if sweeps_path.exists():
        with open(sweeps_path, "r", encoding="utf-8") as f:
            sweeps = json.load(f)

        # 1. Demand sweep vs Lot Utilisation
        d_sweep = sweeps.get("demand_sweep", [])
        if d_sweep:
            x_vals = [d["demand_per_hour"] for d in d_sweep]
            series = {
                "B0_STATIC_FCFS": [d["policies"]["B0_STATIC_FCFS"]["lot_utilisation_pct"] for d in d_sweep],
                "B1_STATIC_AUTO_RELEASE": [d["policies"]["B1_STATIC_AUTO_RELEASE"]["lot_utilisation_pct"] for d in d_sweep],
                "D3_FULL_DYNAMIC": [d["policies"]["D3_FULL_DYNAMIC"]["lot_utilisation_pct"] for d in d_sweep],
            }
            create_sensitivity_line_chart(
                title="Sensitivity: Facility Utilization vs Traffic Demand",
                subtitle="Evaluates load scaling across 30 to 100 drivers/hour",
                x_label="Incoming Demand (Drivers / Hour)",
                y_label="Lot Utilization (%)",
                x_vals=x_vals,
                series_data=series,
                output_path=charts_dir / "sensitivity_demand_vs_utilisation.svg",
            )

        # 2. No-Show sweep vs Slot-Minutes Recovered
        ns_sweep = sweeps.get("no_show_sweep", [])
        if ns_sweep:
            x_vals = [ns["no_show_rate"] * 100.0 for ns in ns_sweep]
            series = {
                "B0_STATIC_FCFS": [ns["policies"]["B0_STATIC_FCFS"]["slot_minutes_recovered"] for ns in ns_sweep],
                "B1_STATIC_AUTO_RELEASE": [ns["policies"]["B1_STATIC_AUTO_RELEASE"]["slot_minutes_recovered"] for ns in ns_sweep],
                "D3_FULL_DYNAMIC": [ns["policies"]["D3_FULL_DYNAMIC"]["slot_minutes_recovered"] for ns in ns_sweep],
            }
            create_sensitivity_line_chart(
                title="Sensitivity: Slot-Minutes Recovered vs No-Show Rate",
                subtitle="Demonstrates resilient capacity reclamation from 5% to 20% driver no-shows",
                x_label="Driver No-Show Probability (%)",
                y_label="Slot-Minutes Recovered (min)",
                x_vals=x_vals,
                series_data=series,
                output_path=charts_dir / "sensitivity_noshow_vs_recovered.svg",
            )

        # 3. Acceptance sweep vs Distance Saved
        acc_sweep = sweeps.get("acceptance_sweep", [])
        if acc_sweep:
            x_vals = [a["acceptance_probability_assumption"] * 100.0 for a in acc_sweep]
            series = {
                "D3_FULL_DYNAMIC (Distance Saved)": [a["results"]["walking_distance_saved_mean_m"] for a in acc_sweep],
            }
            create_sensitivity_line_chart(
                title="Exogenous Sensitivity: Walking Distance Saved vs Driver Compliance",
                subtitle="NOTE: Input behavioral assumption sweep — not an empirical finding",
                x_label="Assumed Driver Upgrade Acceptance Probability (%)",
                y_label="Mean Distance Saved (m)",
                x_vals=x_vals,
                series_data=series,
                output_path=charts_dir / "sensitivity_acceptance_assumption.svg",
            )

    print(f"Generated all publication SVG charts in {charts_dir}")

if __name__ == "__main__":
    generate_all_charts()

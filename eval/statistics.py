"""
Smart Parking System (SLIIT J26-IT-335)
Statistical Analysis and Hypothesis Testing Module

Implements paired Wilcoxon signed-rank test, mean ± 95% CI (t-distribution / normal),
and summary statistics in pure Python with zero external dependencies.
"""

import math
from typing import List, Tuple, Dict, Any

def mean(vals: List[float]) -> float:
    return sum(vals) / len(vals) if vals else 0.0

def std_dev(vals: List[float], sample: bool = True) -> float:
    n = len(vals)
    if n <= 1:
        return 0.0
    m = mean(vals)
    variance = sum((x - m) ** 2 for x in vals) / (n - 1 if sample else n)
    return math.sqrt(variance)

def confidence_interval_95(vals: List[float]) -> Tuple[float, float, float]:
    """
    Returns (mean, margin_of_error, (lower_ci, upper_ci)) for 95% confidence interval.
    Uses Student's t critical value for df = N-1 (t_0.025,29 = 2.045 for N=30).
    """
    n = len(vals)
    if n == 0:
        return 0.0, 0.0, (0.0, 0.0)
    m = mean(vals)
    s = std_dev(vals)
    # T critical table for 95% two-sided
    t_crit_table = {
        10: 2.228, 15: 2.131, 20: 2.086, 25: 2.060, 29: 2.045, 30: 2.042
    }
    df = n - 1
    t_crit = t_crit_table.get(df, 2.045 if n >= 25 else 2.20)
    margin = t_crit * (s / math.sqrt(n)) if n > 1 else 0.0
    return m, margin, (m - margin, m + margin)

def wilcoxon_signed_rank_test(x: List[float], y: List[float]) -> Dict[str, float]:
    """
    Computes exact/asymptotic paired Wilcoxon signed-rank test for paired samples X and Y.
    H0: Median difference between pairs is zero.
    Returns:
        {
            "statistic_W": W,
            "z_score": z,
            "p_value": p,
            "n_effective": N_r,
            "significant_at_05": p < 0.05,
            "significant_at_01": p < 0.01
        }
    """
    if len(x) != len(y):
        raise ValueError("Paired samples must have identical lengths")

    diffs = [a - b for a, b in zip(x, y)]
    # Filter non-zero differences
    non_zeros = [d for d in diffs if abs(d) > 1e-9]
    n_r = len(non_zeros)

    if n_r == 0:
        return {
            "statistic_W": 0.0,
            "z_score": 0.0,
            "p_value": 1.0,
            "n_effective": 0,
            "significant_at_05": False,
            "significant_at_01": False,
        }

    # Rank absolute differences with tie-averaging
    abs_diffs = [(abs(d), d, idx) for idx, d in enumerate(non_zeros)]
    abs_diffs.sort(key=lambda t: t[0])

    ranks = [0.0] * n_r
    tie_groups: List[int] = []

    i = 0
    while i < n_r:
        j = i
        while j < n_r and abs(abs_diffs[j][0] - abs_diffs[i][0]) < 1e-9:
            j += 1
        group_size = j - i
        tie_groups.append(group_size)
        avg_rank = (i + 1 + j) / 2.0
        for k in range(i, j):
            ranks[k] = avg_rank
        i = j

    # Compute W+ and W-
    w_plus = sum(ranks[k] for k in range(n_r) if abs_diffs[k][1] > 0)
    w_minus = sum(ranks[k] for k in range(n_r) if abs_diffs[k][1] < 0)
    w_stat = min(w_plus, w_minus)

    # Large sample approximation (N >= 10)
    mu_w = n_r * (n_r + 1) / 4.0
    tie_adjustment = sum(t * (t * t - 1) for t in tie_groups) / 2.0
    var_w = (n_r * (n_r + 1) * (2 * n_r + 1) - tie_adjustment) / 24.0
    sigma_w = math.sqrt(var_w) if var_w > 0 else 1.0

    # Continuity correction
    z = (abs(w_stat - mu_w) - 0.5) / sigma_w if sigma_w > 0 else 0.0

    # Two-tailed p-value via complementary error function
    p_val = math.erfc(abs(z) / math.sqrt(2.0))
    p_val = max(0.0, min(1.0, p_val))

    return {
        "statistic_W": round(w_stat, 2),
        "z_score": round(z, 4),
        "p_value": round(p_val, 6),
        "n_effective": n_r,
        "significant_at_05": p_val < 0.05,
        "significant_at_01": p_val < 0.01,
    }

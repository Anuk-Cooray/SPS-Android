"""train_eta_model.py
Smart Parking Re-optimization System (J26-IT-335)
Learned Sri Lankan ETA Residual Correction Model Trainer

Trains linear regression / gradient boosting on the residual ratio:
  residual_ratio = actualTravelMin / predictedEtaMinProvider

Evaluates against:
  1. Heuristic Research Baseline (Straight-line x 1.35, 22 km/h)
  2. Uncorrected Provider Prediction (Commercial API nominal)
  3. Learned Ridge Regression Model (v1.0.0-linear)
  4. Learned Gradient Boosting Regressor (when sklearn is present)

Exports deployable coefficients to JSON for zero-dependency serving in Cloud Functions & Flutter.
"""

import os
import csv
import json
import math
import random
from datetime import datetime

MODEL_VERSION = "v1.0.0-linear"
RANDOM_SEED = 42

def load_data(csv_path):
    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # Filter invalid records
    cleaned = []
    for r in rows:
        actual = float(r["actualTravelMin"])
        provider = float(r["predictedEtaMinProvider"])
        baseline = float(r["predictedEtaMinBaseline"])
        if actual > 0 and provider > 0:
            cleaned.append({
                "tripId": r["tripId"],
                "originZone": r["originZone"],
                "distanceKm": float(r["distanceKm"]),
                "hour": int(r["hour"]),
                "isPeakHour": float(r["isPeakHour"]),
                "isWeekend": float(r["isWeekend"]),
                "weatherFlag": float(r["weatherFlag"]),
                "holidayFlag": float(r["holidayFlag"]),
                "predictedEtaMinBaseline": baseline,
                "predictedEtaMinProvider": provider,
                "actualTravelMin": actual,
                "residualRatio": float(r["residualRatio"]),
            })
    return cleaned

def extract_features(rows):
    all_zones = sorted(list({r["originZone"] for r in rows}))
    feature_names = [
        "distanceKm",
        "isPeakHour",
        "isWeekend",
        "weatherFlag",
        "holidayFlag",
        "sin_hour",
        "cos_hour",
    ] + [f"zone_{z}" for z in all_zones]

    X = []
    y = []
    for r in rows:
        hour_rad = 2.0 * math.pi * r["hour"] / 24.0
        row_feat = [
            r["distanceKm"],
            r["isPeakHour"],
            r["isWeekend"],
            r["weatherFlag"],
            r["holidayFlag"],
            math.sin(hour_rad),
            math.cos(hour_rad),
        ]
        for z in all_zones:
            row_feat.append(1.0 if r["originZone"] == z else 0.0)

        X.append(row_feat)
        y.append(r["residualRatio"])

    return X, y, feature_names

def invert_matrix(A):
    """Computes exact matrix inverse via Gauss-Jordan elimination with partial pivoting."""
    n = len(A)
    M = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(A)]
    for i in range(n):
        pivot_row = i
        for k in range(i + 1, n):
            if abs(M[k][i]) > abs(M[pivot_row][i]):
                pivot_row = k
        if pivot_row != i:
            M[i], M[pivot_row] = M[pivot_row], M[i]

        pivot = M[i][i]
        if abs(pivot) < 1e-12:
            pivot = 1e-12 if pivot >= 0 else -1e-12
        for j in range(2 * n):
            M[i][j] /= pivot
        for k in range(n):
            if k != i:
                factor = M[k][i]
                for j in range(2 * n):
                    M[k][j] -= factor * M[i][j]
    return [row[n:] for row in M]

def solve_ridge(X, y, alpha=1.0):
    """Fits Ridge Regression: w = (X^T X + alpha * I)^(-1) X^T y with intercept."""
    # Prepend column of 1s for intercept
    X_ext = [[1.0] + row for row in X]
    num_samples = len(X_ext)
    num_features = len(X_ext[0])

    # Compute X^T * X
    XtX = [[0.0] * num_features for _ in range(num_features)]
    for i in range(num_features):
        for j in range(num_features):
            s = sum(X_ext[k][i] * X_ext[k][j] for k in range(num_samples))
            if i == j and i > 0: # Do not regularize intercept
                s += alpha
            XtX[i][j] = s

    # Compute X^T * y
    Xty = [0.0] * num_features
    for i in range(num_features):
        Xty[i] = sum(X_ext[k][i] * y[k] for k in range(num_samples))

    # Invert XtX
    inv_XtX = invert_matrix(XtX)

    # w = inv(XtX) * Xty
    w = [0.0] * num_features
    for i in range(num_features):
        w[i] = sum(inv_XtX[i][j] * Xty[j] for j in range(num_features))

    intercept = w[0]
    coefficients = w[1:]
    return intercept, coefficients

def predict_ridge(X, intercept, coefficients):
    preds = []
    for row in X:
        val = intercept + sum(c * x for c, x in zip(coefficients, row))
        # Clamp to realistic bounds
        clamped = max(0.5, min(3.0, val))
        preds.append(clamped)
    return preds

def evaluate_metrics(actual, predicted):
    n = len(actual)
    mae = sum(abs(a - p) for a, p in zip(actual, predicted)) / n
    mse = sum((a - p) ** 2 for a, p in zip(actual, predicted)) / n
    rmse = math.sqrt(mse)
    mape = (sum(abs((a - p) / a) for a, p in zip(actual, predicted)) / n) * 100.0
    return mae, rmse, mape

def train_and_evaluate(data_dir, output_dir):
    csv_path = os.path.join(data_dir, "colombo_trips_synthetic.csv")
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Dataset not found at {csv_path}. Run generate_synthetic_trips.py first.")

    rows = load_data(csv_path)
    X, y, feature_names = extract_features(rows)

    # 80/20 train/test split with seed
    random.seed(RANDOM_SEED)
    indices = list(range(len(rows)))
    random.shuffle(indices)
    split_idx = int(0.80 * len(rows))
    train_idx = indices[:split_idx]
    test_idx = indices[split_idx:]

    X_train = [X[i] for i in train_idx]
    y_train = [y[i] for i in train_idx]
    X_test = [X[i] for i in test_idx]

    test_actual = [rows[i]["actualTravelMin"] for i in test_idx]
    test_provider = [rows[i]["predictedEtaMinProvider"] for i in test_idx]
    test_baseline = [rows[i]["predictedEtaMinBaseline"] for i in test_idx]

    print(f"[ETA Model Trainer] Dataset: {len(rows)} trips ({len(train_idx)} train, {len(test_idx)} test)")
    print(f"[ETA Model Trainer] Features ({len(feature_names)}): {feature_names}")

    # Benchmark 1: Heuristic Baseline (22 km/h)
    mae_heur, rmse_heur, mape_heur = evaluate_metrics(test_actual, test_baseline)

    # Benchmark 2: Uncorrected Provider API (ratio = 1.0)
    mae_prov, rmse_prov, mape_prov = evaluate_metrics(test_actual, test_provider)

    # Model 1: Learned Ridge Regression
    intercept, coefficients = solve_ridge(X_train, y_train, alpha=1.0)
    pred_ratios = predict_ridge(X_test, intercept, coefficients)
    pred_minutes_ridge = [p * r for p, r in zip(test_provider, pred_ratios)]
    mae_ridge, rmse_ridge, mape_ridge = evaluate_metrics(test_actual, pred_minutes_ridge)

    # Optional: If sklearn is available, also compare with Gradient Boosting
    gbr_available = False
    mae_gbr, rmse_gbr, mape_gbr = 0.0, 0.0, 0.0
    try:
        from sklearn.ensemble import GradientBoostingRegressor
        gbr = GradientBoostingRegressor(n_estimators=100, max_depth=3, learning_rate=0.08, random_state=RANDOM_SEED)
        gbr.fit(X_train, y_train)
        pred_gbr_ratios = [max(0.5, min(3.0, float(v))) for v in gbr.predict(X_test)]
        pred_minutes_gbr = [p * r for p, r in zip(test_provider, pred_gbr_ratios)]
        mae_gbr, rmse_gbr, mape_gbr = evaluate_metrics(test_actual, pred_minutes_gbr)
        gbr_available = True
    except Exception:
        pass

    print("\n=======================================================")
    print("           MODEL BENCHMARK EVALUATION (TEST SET)       ")
    print("=======================================================")
    print(f"{'Model':<32} {'MAE (min)':<12} {'RMSE (min)':<12} {'MAPE (%)':<10}")
    print("-" * 66)
    print(f"{'Heuristic Baseline (22 km/h)':<32} {mae_heur:<12.2f} {rmse_heur:<12.2f} {mape_heur:<10.2f}")
    print(f"{'Uncorrected Provider API':<32} {mae_prov:<12.2f} {rmse_prov:<12.2f} {mape_prov:<10.2f}")
    print(f"{'Learned Ridge Regression (v1)':<32} {mae_ridge:<12.2f} {rmse_ridge:<12.2f} {mape_ridge:<10.2f}")
    if gbr_available:
        print(f"{'Learned Gradient Boosting (v1)':<32} {mae_gbr:<12.2f} {rmse_gbr:<12.2f} {mape_gbr:<10.2f}")
    print("=======================================================\n")

    improvement_vs_prov = ((mae_prov - mae_ridge) / mae_prov) * 100.0
    improvement_vs_heur = ((mae_heur - mae_ridge) / mae_heur) * 100.0
    print(f"[Results] Ridge model reduces MAE by {improvement_vs_prov:.1f}% vs commercial provider API")
    print(f"[Results] Ridge model reduces MAE by {improvement_vs_heur:.1f}% vs heuristic research baseline")

    coef_dict = {name: round(float(c), 5) for name, c in zip(feature_names, coefficients)}
    model_json = {
        "modelVersion": MODEL_VERSION,
        "modelType": "ridge_regression",
        "description": "Learned Sri Lankan urban ETA residual correction model (J26-IT-335)",
        "trainedAt": datetime.now().isoformat(),
        "randomSeed": RANDOM_SEED,
        "intercept": round(float(intercept), 5),
        "coefficients": coef_dict,
        "featureNames": feature_names,
        "formula": "correctedEta = providerEta * clamp(intercept + dot(features, coefficients), 0.5, 3.0)",
        "performance": {
            "testSampleCount": len(test_idx),
            "maeMinutes": round(mae_ridge, 3),
            "rmseMinutes": round(rmse_ridge, 3),
            "mapePercent": round(mape_ridge, 2),
            "baselineComparison": {
                "heuristicBaselineMae": round(mae_heur, 3),
                "uncorrectedProviderMae": round(mae_prov, 3),
                "maeReductionVsProviderPercent": round(improvement_vs_prov, 1),
                "maeReductionVsHeuristicPercent": round(improvement_vs_heur, 1),
            },
        },
    }

    os.makedirs(output_dir, exist_ok=True)
    out_file = os.path.join(output_dir, "eta_model_v1.json")
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(model_json, f, indent=2)

    print(f"[ETA Model Trainer] Saved deployable model JSON to: {out_file}")
    return model_json

if __name__ == "__main__":
    ml_root = os.path.dirname(__file__)
    data_dir = os.path.join(ml_root, "data")
    models_dir = os.path.join(ml_root, "models")
    train_and_evaluate(data_dir, models_dir)

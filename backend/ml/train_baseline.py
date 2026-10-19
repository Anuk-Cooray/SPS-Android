"""Time-split evaluation and final refit on SYNTHETIC hourly occupancy."""

import argparse
import json
import pickle
from datetime import timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor

from ml.generate_synthetic_data import DEFAULT_DATA
from ml.pipeline import FEATURES, load_history, prophet_frame
from ml.predict import ARTIFACTS, model_predictions, predict


def select_model(requested: str) -> tuple[str, object | None]:
    if requested == "gradient_boosting":
        return requested, None
    try:
        from prophet import Prophet
    except ImportError:
        if requested == "prophet":
            raise RuntimeError("Prophet requested but not installed") from None
        return "gradient_boosting", None
    return "prophet", Prophet


def fit_model(kind: str, prophet_class: object | None, frame: pd.DataFrame) -> object:
    if kind == "prophet":
        model = prophet_class(
            daily_seasonality=True, weekly_seasonality=True, yearly_seasonality=False
        )
        model.add_regressor("rain_mm")
        model.fit(prophet_frame(frame))
        return model
    model = GradientBoostingRegressor(random_state=335, n_estimators=100, max_depth=3)
    model.fit(frame[FEATURES], frame["occupancy_rate"])
    return model


def scores(actual: np.ndarray, predicted: np.ndarray) -> dict:
    actual, predicted = np.asarray(actual), np.asarray(predicted)
    if not len(actual):
        raise ValueError("Cannot evaluate an empty test set")
    error = actual - predicted
    nonzero = actual > 0
    return {
        "mae": float(np.mean(np.abs(error))),
        "rmse": float(np.sqrt(np.mean(error**2))),
        "mape_percent": (
            float(np.mean(np.abs(error[nonzero] / actual[nonzero])) * 100)
            if nonzero.any()
            else None
        ),
        "mape_nonzero_count": int(nonzero.sum()),
        "test_rows": len(actual),
    }


def time_split(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    # Exactly the final 168 hourly timestamps, with no random shuffling.
    cutoff = frame["timestamp"].max() - pd.Timedelta(days=7) + pd.Timedelta(hours=1)
    train = frame[frame["timestamp"] < cutoff].copy()
    test = frame[frame["timestamp"] >= cutoff].copy()
    if len(test) != 168 or len(train) < 168:
        raise ValueError("Need at least 14 complete days per lot")
    return train, test


def save_plot(bundle: dict, output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    figure, axes = plt.subplots(len(bundle["lots"]), 1, figsize=(10, 8), squeeze=False)
    for axis, lot_id in zip(axes[:, 0], bundle["lots"]):
        points = predict(bundle, lot_id)
        ts = pd.to_datetime([point["ts"] for point in points], utc=True).tz_convert(
            "Asia/Colombo"
        )
        axis.plot(
            ts,
            [point["yhat"] for point in points],
            color="black",
            label="Baseline prediction",
        )
        axis.fill_between(
            ts,
            [point["yhat_lower"] for point in points],
            [point["yhat_upper"] for point in points],
            color="gray",
            alpha=0.25,
            label="Training residual band (not calibrated)",
        )
        axis.set(title=lot_id, ylim=(0, 1), ylabel="Occupancy fraction")
        axis.legend(fontsize=7, loc="upper right")
    axes[-1, 0].set_xlabel("Asia/Colombo — next 24 hours after synthetic history")
    figure.suptitle("SYNTHETIC DEMO — baseline demand forecast")
    figure.tight_layout(rect=(0, 0, 1, 0.95))
    figure.savefig(output, dpi=150)
    plt.close(figure)


def train(
    data_path: Path = DEFAULT_DATA,
    artifacts: Path = ARTIFACTS,
    requested: str = "auto",
    plot: bool = True,
) -> dict:
    data = load_history(data_path)
    kind, prophet_class = select_model(requested)
    reports, fitted = {}, {}
    for lot_id, group in data.groupby("lot_id", sort=True):
        group = group.reset_index(drop=True)
        training, test = time_split(group)
        if training["was_imputed"].any() or test["was_imputed"].any():
            raise ValueError(
                "Evaluation needs observed hourly occupancy; imputed targets are not ground truth"
            )
        evaluation_model = fit_model(kind, prophet_class, training)
        # Unknown future rainfall/events are zero both in holdout evaluation and demo prediction.
        future = test.copy()
        future["rain_mm"], future["event_flag"] = 0.0, 0
        predictions = model_predictions(kind, evaluation_model, future)
        lookup = training.set_index("timestamp")["occupancy_rate"]
        naive = lookup.reindex(test["timestamp"] - pd.Timedelta(days=7)).to_numpy()
        if not np.isfinite(naive).all():
            raise ValueError("Missing same-hour-last-week baseline observations")
        actual = test["occupancy_rate"].to_numpy()
        reports[lot_id] = {
            "model": scores(actual, predictions),
            "naive_last_week": scores(actual, naive),
            "train_rows": len(training),
            "train_end": training["timestamp"].max().isoformat(),
            "test_start": test["timestamp"].min().isoformat(),
            "test_end": test["timestamp"].max().isoformat(),
        }
        # Holdout metrics are frozen first. Refit separately for the demo artifact.
        final_model = fit_model(kind, prophet_class, group)
        residuals = np.abs(
            group["occupancy_rate"].to_numpy()
            - model_predictions(kind, final_model, group)
        )
        fitted[lot_id] = {
            "model": final_model,
            "residual_radius": float(np.quantile(residuals, 0.9)),
        }
    bundle = {
        "schema_version": 1,
        "synthetic": True,
        "model_kind": kind,
        "history_end": data["timestamp"].max().isoformat(),
        "lots": fitted,
    }
    report = {
        "synthetic": True,
        "training_seed": 335,
        "model_kind": kind,
        "fallback_reason": (
            "Prophet unavailable; using scikit-learn"
            if requested == "auto" and kind != "prophet"
            else None
        ),
        "evaluated_at": pd.Timestamp.now(tz=timezone.utc).isoformat(),
        "evaluation": "Last seven days; forecast rain/event inputs = zero; MAPE excludes zero targets",
        "band": "90th percentile absolute in-sample residual; illustrative, not calibrated coverage",
        "final_refit": "All history, after holdout evaluation",
        "lots": reports,
    }
    artifacts.mkdir(parents=True, exist_ok=True)
    with (artifacts / "baseline.pkl").open("wb") as stream:
        pickle.dump(bundle, stream)
    (artifacts / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    if plot:
        save_plot(bundle, artifacts / "forecast_demo.png")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--artifacts", type=Path, default=ARTIFACTS)
    parser.add_argument(
        "--model", choices=["auto", "prophet", "gradient_boosting"], default="auto"
    )
    args = parser.parse_args()
    print(json.dumps(train(args.data, args.artifacts, args.model), indent=2))


if __name__ == "__main__":
    main()

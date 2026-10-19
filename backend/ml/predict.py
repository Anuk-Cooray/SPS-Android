"""Load a locally trained bundle and forecast occupancy (not monetary amounts)."""

import argparse
import json
import pickle
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from ml.pipeline import FEATURES, add_features

ARTIFACTS = Path(__file__).parent / "artifacts"
DEFAULT_MODEL = ARTIFACTS / "baseline.pkl"


def load_bundle(path: Path = DEFAULT_MODEL) -> dict:
    # Only load artifacts generated locally: pickle is not safe for untrusted files.
    with path.open("rb") as stream:
        return pickle.load(stream)


def future_frame(start: datetime, horizon_hours: int) -> pd.DataFrame:
    if start.utcoffset() is None:
        raise ValueError("Forecast start must include a timezone")
    if not 1 <= horizon_hours <= 168:
        raise ValueError("Horizon must be between 1 and 168 hours")
    return add_features(
        pd.DataFrame(
            {
                "timestamp": pd.date_range(
                    start=start, periods=horizon_hours, freq="h"
                ).tz_convert("UTC"),
                "rain_mm": 0.0,
                "event_flag": 0,
            }
        )
    )


def model_predictions(kind: str, model: object, frame: pd.DataFrame) -> np.ndarray:
    if kind == "prophet":
        ds = (
            pd.to_datetime(frame["timestamp"], utc=True)
            .dt.tz_convert("Asia/Colombo")
            .dt.tz_localize(None)
        )
        output = model.predict(
            pd.DataFrame({"ds": ds, "rain_mm": frame["rain_mm"].to_numpy()})
        )
        return np.clip(output["yhat"].to_numpy(), 0, 1)
    return np.clip(model.predict(frame[FEATURES]), 0, 1)


def predict(
    bundle: dict, lot_id: str, horizon_hours: int = 24, start: datetime | None = None
) -> list[dict]:
    if lot_id not in bundle["lots"]:
        raise ValueError(f"Unknown lot: {lot_id}")
    if start is None:
        start = pd.Timestamp(bundle["history_end"]).to_pydatetime() + pd.Timedelta(
            hours=1
        )
    frame = future_frame(start, horizon_hours)
    fitted = bundle["lots"][lot_id]
    values = model_predictions(bundle["model_kind"], fitted["model"], frame)
    radius = fitted["residual_radius"]
    return [
        {
            "ts": ts.isoformat(),
            "yhat": float(value),
            "yhat_lower": float(max(0, value - radius)),
            "yhat_upper": float(min(1, value + radius)),
            "demand_level": float(value),
        }
        for ts, value in zip(frame["timestamp"], values)
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--lot-id", default="lot-main")
    parser.add_argument("--horizon-hours", type=int, default=24)
    parser.add_argument("--start", type=datetime.fromisoformat)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    points = predict(
        load_bundle(args.model), args.lot_id, args.horizon_hours, args.start
    )
    content = json.dumps(points, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content + "\n")
        print(f"SYNTHETIC forecast: {len(points)} hours → {args.output}")
    else:
        print(content)


if __name__ == "__main__":
    main()

"""Load aware history, resolve duplicates, resample and create occupancy features."""

from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

FEATURES = ["hour", "dow", "is_weekend", "is_peak", "rain_mm", "event_flag"]
REQUIRED = {
    "timestamp",
    "lot_id",
    "occupied_slots",
    "capacity",
    "entries",
    "rain_mm",
    "event_flag",
}


def aware_timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.utcoffset() is None:
        raise ValueError("Every history timestamp must include a timezone")
    return parsed


def add_features(frame: pd.DataFrame) -> pd.DataFrame:
    data = frame.copy()
    local = pd.to_datetime(data["timestamp"], utc=True).dt.tz_convert("Asia/Colombo")
    data["hour"] = local.dt.hour
    data["dow"] = local.dt.dayofweek
    data["is_weekend"] = (data["dow"] >= 5).astype(int)
    minutes = local.dt.hour * 60 + local.dt.minute
    data["is_peak"] = (
        (data["dow"] < 5)
        & (((minutes >= 450) & (minutes < 570)) | ((minutes >= 930) & (minutes < 1050)))
    ).astype(int)
    return data


def load_history(path: Path) -> pd.DataFrame:
    data = pd.read_csv(path)
    if not REQUIRED.issubset(data.columns) or data.empty:
        raise ValueError(
            "History must contain all dictionary columns and at least one row"
        )
    data["timestamp"] = pd.to_datetime(data["timestamp"].map(aware_timestamp), utc=True)
    if data["lot_id"].isna().any() or (data["lot_id"].astype(str).str.len() == 0).any():
        raise ValueError("Lot IDs must not be empty")
    for name in REQUIRED - {"timestamp", "lot_id"}:
        data[name] = pd.to_numeric(data[name], errors="raise")
        if not np.isfinite(data[name]).all():
            raise ValueError(f"Non-finite values in {name}")
    if (
        (data["capacity"] <= 0)
        | (data["occupied_slots"] < 0)
        | (data["occupied_slots"] > data["capacity"])
        | (data["entries"] < 0)
        | (data["rain_mm"] < 0)
        | ~data["event_flag"].isin([0, 1])
    ).any():
        raise ValueError(
            "Invalid capacity, occupancy, arrivals, rainfall or event flag"
        )
    # Last record wins for a duplicate timestamp; never merge separate lots.
    data = data.drop_duplicates(["lot_id", "timestamp"], keep="last")
    frames = []
    for lot_id, group in data.groupby("lot_id", sort=True):
        hourly = (
            group.sort_values("timestamp")
            .set_index("timestamp")
            .tz_convert("Asia/Colombo")
            .resample("h")
            .agg(
                {
                    "occupied_slots": "last",
                    "capacity": "last",
                    "entries": "sum",
                    "rain_mm": "mean",
                    "event_flag": "max",
                }
            )
        )
        hourly["was_imputed"] = hourly["occupied_slots"].isna()
        # Forward fill uses only past observations; no test-to-train interpolation.
        hourly[["occupied_slots", "capacity", "rain_mm", "event_flag"]] = hourly[
            ["occupied_slots", "capacity", "rain_mm", "event_flag"]
        ].ffill()
        hourly["lot_id"] = lot_id
        hourly["occupancy_rate"] = hourly["occupied_slots"] / hourly["capacity"]
        hourly.index = hourly.index.tz_convert("UTC")
        frames.append(hourly.reset_index())
    return add_features(pd.concat(frames, ignore_index=True))


def prophet_frame(frame: pd.DataFrame) -> pd.DataFrame:
    """Prophet requires naive ds; use Colombo wall time only at this boundary."""
    return pd.DataFrame(
        {
            "ds": pd.to_datetime(frame["timestamp"], utc=True)
            .dt.tz_convert("Asia/Colombo")
            .dt.tz_localize(None),
            "y": frame["occupancy_rate"].to_numpy(),
            "rain_mm": frame["rain_mm"].to_numpy(),
        }
    )

import builtins
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from ml.generate_synthetic_data import generate, read_mock_lots
from ml.pipeline import add_features, load_history, prophet_frame
from ml.predict import future_frame, load_bundle, predict
from ml.train_baseline import scores, select_model, time_split, train


def csv_path(tmp_path: Path, data: pd.DataFrame) -> Path:
    path = tmp_path / "history.csv"
    data.to_csv(path, index=False)
    return path


def test_generator_seed_bounds_and_flutter_ids():
    data = generate()
    pd.testing.assert_frame_equal(data, generate())
    assert len(data) == 90 * 24 * 3
    assert read_mock_lots() == {"lot-main": 24, "lot-new-p2": 30, "lot-sports": 18}
    assert set(data.lot_id) == set(read_mock_lots())
    assert ((data.occupied_slots >= 0) & (data.occupied_slots <= data.capacity)).all()
    assert (data.rain_mm > 0).any()
    assert (data.event_flag == 1).any()


def test_dedupe_sort_and_causal_gap_fill(tmp_path):
    data = generate(days=1)
    # Drop one timestamp in one lot; insert a duplicate with a replacement value.
    missing = data.iloc[1].timestamp
    data = data.drop(index=1)
    duplicate = data.iloc[[0]].copy()
    duplicate["occupied_slots"] = 3
    data = pd.concat([data.iloc[::-1], duplicate], ignore_index=True)
    result = load_history(csv_path(tmp_path, data))
    group = result[result.lot_id == "lot-main"].reset_index(drop=True)
    assert len(group) == 24
    assert group.timestamp.is_monotonic_increasing
    assert group.iloc[0].occupied_slots == 3
    assert group.iloc[1].occupied_slots == 3
    assert group.iloc[1].timestamp == pd.Timestamp(missing).tz_convert("UTC")
    assert group.iloc[1].was_imputed
    assert not group.iloc[2].was_imputed
    assert group.iloc[1].entries == 0
    assert result.groupby("lot_id").size().to_dict() == {
        lot: 24 for lot in read_mock_lots()
    }


@pytest.mark.parametrize(
    "column,value",
    [
        ("timestamp", "2026-07-01T00:00:00"),
        ("capacity", 0),
        ("occupied_slots", -1),
        ("occupied_slots", 999),
        ("rain_mm", -1),
        ("rain_mm", float("nan")),
        ("entries", -1),
        ("event_flag", 2),
        ("lot_id", ""),
    ],
)
def test_invalid_history_rejected(tmp_path, column, value):
    data = generate(days=1)
    data.loc[0, column] = value
    with pytest.raises(ValueError):
        load_history(csv_path(tmp_path, data))


def test_features_use_colombo_and_prophet_boundary():
    data = add_features(
        pd.DataFrame(
            {
                "timestamp": pd.to_datetime(
                    ["2026-10-19T02:30:00Z", "2026-10-18T02:30:00Z"], utc=True
                ),
                "rain_mm": [0, 1],
                "occupancy_rate": [0.5, 0.2],
            }
        )
    )
    assert data.hour.tolist() == [8, 8]
    assert data.is_weekend.tolist() == [0, 1]
    assert data.is_peak.tolist() == [1, 0]
    prophet = prophet_frame(data)
    assert prophet.ds.dt.tz is None
    assert prophet.ds.dt.hour.tolist() == [8, 8]
    assert prophet.y.tolist() == [0.5, 0.2]


def test_time_split_keeps_last_seven_days(tmp_path):
    data = load_history(csv_path(tmp_path, generate(days=20)))
    training, test = time_split(data[data.lot_id == "lot-main"])
    assert len(test) == 168
    assert len(training) == 13 * 24
    assert training.timestamp.max() < test.timestamp.min()
    assert set(test.timestamp - pd.Timedelta(days=7)).issubset(set(training.timestamp))


def test_short_history_rejected(tmp_path):
    data = load_history(csv_path(tmp_path, generate(days=8)))
    with pytest.raises(ValueError, match="14 complete days"):
        time_split(data[data.lot_id == "lot-main"])


def test_mape_excludes_zero_targets():
    result = scores(np.array([0, 0.5]), np.array([0.1, 0.4]))
    assert result["mae"] == pytest.approx(0.1)
    assert result["mape_percent"] == pytest.approx(20)
    assert result["mape_nonzero_count"] == 1
    assert scores(np.zeros(2), np.zeros(2))["mape_percent"] is None


def test_auto_fallback_only_when_prophet_unavailable(monkeypatch):
    original = builtins.__import__

    def without_prophet(name, *args, **kwargs):
        if name == "prophet":
            raise ImportError("Not installed for this test")
        return original(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", without_prophet)
    assert select_model("auto") == ("gradient_boosting", None)
    with pytest.raises(RuntimeError, match="not installed"):
        select_model("prophet")


def test_future_requires_aware_time_and_bounded_horizon():
    with pytest.raises(ValueError, match="timezone"):
        future_frame(datetime(2026, 10, 19), 24)
    with pytest.raises(ValueError, match="Horizon"):
        future_frame(datetime.fromisoformat("2026-10-19T00:00:00+00:00"), 169)


def test_train_reload_forecast_and_metric_artifacts(tmp_path):
    data = csv_path(tmp_path, generate(days=20))
    artifacts = tmp_path / "artifacts"
    report = train(data, artifacts, requested="gradient_boosting", plot=False)
    assert report["synthetic"] is True
    assert len(report["lots"]) == 3
    assert (artifacts / "metrics.json").is_file()
    bundle = load_bundle(artifacts / "baseline.pkl")
    for lot, metrics in report["lots"].items():
        assert metrics["model"]["test_rows"] == 168
        assert metrics["naive_last_week"]["test_rows"] == 168
        points = predict(bundle, lot)
        assert len(points) == 24
        assert pd.Timestamp(points[0]["ts"]) > pd.Timestamp(bundle["history_end"])
        for point in points:
            assert 0 <= point["yhat_lower"] <= point["yhat"] <= point["yhat_upper"] <= 1
            assert point["demand_level"] == point["yhat"]
    with pytest.raises(ValueError, match="Unknown lot"):
        predict(bundle, "missing")

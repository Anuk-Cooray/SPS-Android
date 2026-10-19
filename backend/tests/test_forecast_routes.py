from datetime import datetime
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import forecast_service as module
from app.services.forecast_service import (
    ForecastService,
    ForecastUnavailable,
    get_forecast_service,
)
from ml.generate_synthetic_data import generate
from ml.predict import load_bundle
from ml.train_baseline import train

NOW = datetime.fromisoformat("2026-10-19T08:45:00+05:30")
PAYLOAD = {
    "booking_id": "BK-FORECAST",
    "lot_id": "lot-main",
    "entry_time": "2026-10-19T10:00:00+05:30",
    "exit_time": "2026-10-19T11:00:00+05:30",
}


@pytest.fixture(scope="module")
def model_files(tmp_path_factory):
    root = tmp_path_factory.mktemp("forecast-model")
    data = root / "history.csv"
    generate(days=20).to_csv(data, index=False)
    train(data, root / "artifacts", requested="gradient_boosting", plot=False)
    return data, root / "artifacts" / "baseline.pkl"


@pytest.fixture
def service(model_files):
    data, model = model_files
    return ForecastService(model_path=model, data_path=data, now=lambda: NOW)


@pytest.fixture
def client(service):
    app.dependency_overrides[get_forecast_service] = lambda: service
    with TestClient(app) as instance:
        yield instance
    app.dependency_overrides.pop(get_forecast_service, None)


def test_future_hours_are_current_colombo_boundaries_in_utc(client):
    response = client.get("/api/v1/forecast/demand", params={"lot_id": "lot-main"})
    assert response.status_code == 200
    points = response.json()
    assert len(points) == 24
    assert points[0]["ts"] == "2026-10-19T03:30:00Z"  # 09:00 Colombo, not 09:30.
    for point in points:
        assert 0 <= point["yhat_lower"] <= point["yhat"] <= point["yhat_upper"] <= 1
        assert point["demand_level"] == point["yhat"]


@pytest.mark.parametrize("horizon", [0, -1, 169, "bad"])
def test_invalid_horizon(client, horizon):
    response = client.get(
        "/api/v1/forecast/demand",
        params={"lot_id": "lot-main", "horizon_hours": horizon},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_unknown_lot_and_missing_lot(client):
    assert (
        client.get("/api/v1/forecast/demand", params={"lot_id": "unknown"}).status_code
        == 404
    )
    assert client.get("/api/v1/forecast/demand").status_code == 422


def test_model_load_cached_across_lots_and_quotes(client, monkeypatch):
    original = module.load_bundle
    calls = []

    def counted(path):
        calls.append(path)
        return original(path)

    monkeypatch.setattr(module, "load_bundle", counted)
    for lot_id in ["lot-main", "lot-new-p2", "lot-sports"]:
        assert (
            client.get("/api/v1/forecast/demand", params={"lot_id": lot_id}).status_code
            == 200
        )
    assert client.post("/api/v1/billing/quote", json=PAYLOAD).status_code == 200
    assert len(calls) == 1


def test_quote_uses_decimal_forecast_for_exit_hour(client, service):
    level, hour = service.demand_for_hour(
        "lot-main", datetime.fromisoformat(PAYLOAD["exit_time"])
    )
    response = client.post("/api/v1/billing/quote", json=PAYLOAD)
    explicit = client.post(
        "/api/v1/billing/quote", json={**PAYLOAD, "demand_level": str(level)}
    )
    assert response.status_code == 200
    assert isinstance(level, Decimal)
    assert hour.isoformat() == "2026-10-19T05:30:00+00:00"
    assert response.json()["total"] == explicit.json()["total"]
    assert "Synthetic forecast demand" in response.json()["explanation"]
    assert "one multiplier" in response.json()["explanation"]


def test_high_demand_reaches_pricing_engine_and_override_bypasses_forecast(
    client, service, monkeypatch
):
    calls = []

    def high_demand(lot_id, timestamp):
        calls.append((lot_id, timestamp))
        return Decimal("0.9"), timestamp

    monkeypatch.setattr(service, "demand_for_hour", high_demand)
    assert client.post("/api/v1/billing/quote", json=PAYLOAD).json()["total"] == 150
    assert (
        client.post(
            "/api/v1/billing/quote", json={**PAYLOAD, "demand_level": "0"}
        ).json()["total"]
        == 100
    )
    assert len(calls) == 1


def test_missing_model_returns_503_but_explicit_quote_still_works(
    client, service, tmp_path
):
    service.model_path = tmp_path / "missing.pkl"
    response = client.get("/api/v1/forecast/demand", params={"lot_id": "lot-main"})
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "FORECAST_UNAVAILABLE"
    assert client.post("/api/v1/billing/quote", json=PAYLOAD).status_code == 503
    assert (
        client.post(
            "/api/v1/billing/quote", json={**PAYLOAD, "demand_level": "0.5"}
        ).status_code
        == 200
    )
    assert (
        client.post(
            "/api/v1/billing/quote", json={**PAYLOAD, "extension_minutes": 61}
        ).status_code
        == 422
    )
    # Invalid stays must not become model-availability failures.
    assert (
        client.post(
            "/api/v1/billing/quote",
            json={**PAYLOAD, "exit_time": PAYLOAD["entry_time"]},
        ).status_code
        == 422
    )


def test_corrupt_model_is_reported_as_unavailable(tmp_path):
    path = tmp_path / "broken.pkl"
    path.write_bytes(b"not a pickle")
    with pytest.raises(ForecastUnavailable):
        ForecastService(model_path=path).get_demand("lot-main")


def test_retrain_disabled_by_default(client, monkeypatch):
    monkeypatch.delenv("DEBUG", raising=False)
    response = client.post("/api/v1/forecast/retrain")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "DEBUG_REQUIRED"


def test_retrain_route_is_guarded_and_returns_summary(client, service, monkeypatch):
    monkeypatch.setenv("DEBUG", "true")
    monkeypatch.setattr(
        service,
        "retrain",
        lambda: {"model_kind": "gradient_boosting", "lots": {"lot-main": {}}},
    )
    response = client.post("/api/v1/forecast/retrain")
    assert response.status_code == 200
    assert response.json() == {
        "status": "retrained",
        "synthetic": True,
        "model_kind": "gradient_boosting",
        "lots": ["lot-main"],
    }


def test_failed_retrain_keeps_loaded_model(service, monkeypatch):
    before = service.get_demand("lot-main")

    def broken(*args, **kwargs):
        raise RuntimeError("Training failed")

    monkeypatch.setattr(module, "train", broken)
    with pytest.raises(ForecastUnavailable, match="Retraining failed"):
        service.retrain()
    assert service.get_demand("lot-main") == before


def test_successful_retrain_replaces_bundle_and_artifacts(
    model_files, tmp_path, monkeypatch
):
    data, model = model_files
    target = tmp_path / "model.pkl"
    target.write_bytes(model.read_bytes())
    service = ForecastService(model_path=target, data_path=data, now=lambda: NOW)
    previous = service._model()
    monkeypatch.setenv("MPLCONFIGDIR", str(tmp_path / "matplotlib"))
    # Explicitly select the fallback to keep this test independent of optional Prophet.
    monkeypatch.setattr(
        module,
        "train",
        lambda source, directory: train(
            source, directory, requested="gradient_boosting"
        ),
    )
    result = service.retrain()
    assert result["model_kind"] == "gradient_boosting"
    assert service._model() is not previous
    assert (tmp_path / "metrics.json").exists()
    assert (tmp_path / "forecast_demo.png").read_bytes().startswith(b"\x89PNG")
    assert load_bundle(target)["synthetic"] is True
    assert len(service.get_demand("lot-main", 1)) == 1


def test_openapi_contains_forecast_routes(client):
    paths = client.get("/openapi.json").json()["paths"]
    assert "/api/v1/forecast/demand" in paths
    assert "/api/v1/forecast/retrain" in paths

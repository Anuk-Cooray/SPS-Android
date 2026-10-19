from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)
PAYLOAD = {
    "booking_id": "BK-DEMO",
    "lot_id": "lot-main",
    "entry_time": "2026-10-19T10:00:00+05:30",
    "exit_time": "2026-10-19T11:00:00+05:30",
    "demand_level": "0.5",
}


def test_health_and_openapi_docs():
    assert client.get("/api/v1/health").json() == {"status": "ok"}
    assert client.get("/docs").status_code == 200
    assert "/api/v1/billing/quote" in client.get("/openapi.json").json()["paths"]


def test_quote_uses_registered_rate_and_utc():
    response = client.post("/api/v1/billing/quote", json=PAYLOAD)
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 100
    assert data["entry_time"] == "2026-10-19T04:30:00Z"
    assert data["booking_id"] == "BK-DEMO"
    assert sum(item["amount"] for item in data["line_items"]) == data["total"]


def test_unknown_lot_error():
    response = client.post(
        "/api/v1/billing/quote", json={**PAYLOAD, "lot_id": "missing"}
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "LOT_NOT_FOUND"


def test_naive_timestamp_validation_error():
    response = client.post(
        "/api/v1/billing/quote", json={**PAYLOAD, "entry_time": "2026-10-19T10:00:00"}
    )
    assert response.status_code == 422
    assert set(response.json()["error"]) == {"code", "message"}


def test_invalid_duration_error():
    response = client.post(
        "/api/v1/billing/quote", json={**PAYLOAD, "exit_time": PAYLOAD["entry_time"]}
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_QUOTE"


def test_unpaired_upgrade_rejected():
    response = client.post(
        "/api/v1/billing/quote", json={**PAYLOAD, "upgrade_from_slot_id": "A-06"}
    )
    assert response.status_code == 422


def test_framework_not_found_uses_error_envelope():
    response = client.get("/api/v1/missing")
    assert response.status_code == 404
    assert set(response.json()["error"]) == {"code", "message"}


def test_arrival_fee_is_a_separate_booked_charge():
    response = client.post(
        "/api/v1/billing/quote", json={**PAYLOAD, "arrival_extension_fee": 50}
    )
    assert response.status_code == 200
    assert response.json()["total"] == 150
    assert any(
        item["label"] == "Arrival deadline extension" and item["amount"] == 50
        for item in response.json()["line_items"]
    )


def test_recorded_upgrade_is_visible_without_inventing_a_rate_delta():
    response = client.post(
        "/api/v1/billing/quote",
        json={**PAYLOAD, "upgrade_from_slot_id": "A-06", "upgrade_to_slot_id": "B-01"},
    )
    assert response.status_code == 200
    assert response.json()["total"] == 100
    assert response.json()["line_items"][-1] == {
        "label": "Upgrade A-06 → B-01",
        "qty": 1,
        "unit": "upgrade",
        "amount": 0,
    }

import hashlib
import hmac
import json
import time
from decimal import Decimal

import pytest
import stripe
from fastapi.testclient import TestClient

from app.core.config import PaymentSettings
from app.main import app
from app.repositories.invoice_repository import InMemoryInvoiceRepository
from app.services.invoice_service import InvoiceService, get_invoice_service
from app.services.payments.payhere import notification_hash

PAYLOAD = {
    "booking_id": "BK-PAYMENT",
    "lot_id": "lot-main",
    "entry_time": "2026-10-19T10:00:00+05:30",
    "exit_time": "2026-10-19T11:00:00+05:30",
    "demand_level": "0.5",
}


@pytest.fixture
def service():
    return InvoiceService(InMemoryInvoiceRepository(), PaymentSettings())


@pytest.fixture
def client(service, monkeypatch):
    monkeypatch.setenv("DEBUG", "true")
    app.dependency_overrides[get_invoice_service] = lambda: service
    with TestClient(app) as instance:
        yield instance
    app.dependency_overrides.pop(get_invoice_service, None)


def invoice(client, payload=None):
    quote = client.post("/api/v1/billing/quote", json=payload or PAYLOAD)
    assert quote.status_code == 200
    response = client.post(
        "/api/v1/billing/invoices",
        json={"booking_id": quote.json()["booking_id"], "quote": quote.json()},
    )
    assert response.status_code == 200
    return response.json()


def start(client, inv, method="payhere"):
    response = client.post(
        f"/api/v1/billing/invoices/{inv['id']}/pay", json={"method": method}
    )
    assert response.status_code == 200
    return response.json()


def mock_callback(session, **changes):
    return {
        "invoice_id": session["invoice_id"],
        "session_id": session["id"],
        "token": session["mock_webhook_token"],
        "status": "paid",
        "amount_minor": session["amount_minor"],
        "currency": session["currency"],
        **changes,
    }


def test_quote_invoice_pay_mock_webhook_status_and_retry(client):
    inv = invoice(client)
    assert inv["status"] == "pending"
    session = start(client, inv)
    assert session["provider"] == "mock" and session["is_mock"] is True
    assert session["status"] == "pending"
    assert start(client, inv)["id"] == session["id"]
    assert (
        client.get(f"/api/v1/billing/invoices/{inv['id']}").json()["status"]
        == "pending"
    )
    response = client.post("/api/v1/billing/webhooks/mock", json=mock_callback(session))
    assert response.status_code == 200 and response.json()["status"] == "paid"
    assert (
        client.post(
            "/api/v1/billing/webhooks/mock", json=mock_callback(session)
        ).json()["duplicate"]
        is True
    )
    assert (
        client.get(f"/api/v1/billing/invoices/{inv['id']}").json()["status"] == "paid"
    )
    assert start(client, inv, "stripe")["id"] == session["id"]
    assert (
        client.post(
            "/api/v1/billing/webhooks/mock",
            json=mock_callback(session, status="failed"),
        ).json()["status"]
        == "paid"
    )


def test_guard_waits_and_can_switch_to_digital(client):
    inv = invoice(client)
    session = start(client, inv, "guard")
    assert session["status"] == "awaiting_guard"
    assert session["provider"] == "guard"
    assert start(client, inv, "guard")["id"] == session["id"]
    assert (
        client.get(f"/api/v1/billing/invoices/{inv['id']}").json()["status"]
        == "awaiting_guard"
    )
    assert start(client, inv, "stripe")["status"] == "pending"


def test_forged_quote_and_booking_mismatch_rejected(client):
    quote = client.post("/api/v1/billing/quote", json=PAYLOAD).json()
    quote["total"] = 1
    response = client.post(
        "/api/v1/billing/invoices",
        json={"booking_id": PAYLOAD["booking_id"], "quote": quote},
    )
    assert response.status_code == 422
    quote = client.post("/api/v1/billing/quote", json=PAYLOAD).json()
    assert (
        client.post(
            "/api/v1/billing/invoices", json={"booking_id": "different", "quote": quote}
        ).status_code
        == 422
    )


def test_invoice_creation_retry_reuses_same_invoice(client):
    assert invoice(client)["id"] == invoice(client)["id"]
    assert (
        client.post(
            "/api/v1/billing/invoices",
            json={
                "booking_id": PAYLOAD["booking_id"],
                "quote": client.post(
                    "/api/v1/billing/quote", json={**PAYLOAD, "demand_level": "0.9"}
                ).json(),
            },
        ).status_code
        == 409
    )


@pytest.mark.parametrize(
    "changes",
    [
        {"token": "bad"},
        {"token": "\u2603"},
        {"amount_minor": 1},
        {"currency": "USD"},
        {"amount_minor": True},
        {"status": "pending"},
    ],
)
def test_mock_tampering_rejected(client, changes):
    inv = invoice(client)
    session = start(client, inv)
    assert (
        client.post(
            "/api/v1/billing/webhooks/mock", json=mock_callback(session, **changes)
        ).status_code
        == 400
    )
    assert (
        client.get(f"/api/v1/billing/invoices/{inv['id']}").json()["status"]
        == "pending"
    )


def test_mock_disabled_without_debug(client, monkeypatch):
    session = start(client, invoice(client))
    monkeypatch.setenv("DEBUG", "false")
    assert (
        client.post(
            "/api/v1/billing/webhooks/mock", json=mock_callback(session)
        ).status_code
        == 403
    )


def test_failed_attempt_can_retry_but_late_failure_does_not_override_latest(
    client, service
):
    inv = invoice(client)
    first = start(client, inv)
    client.post(
        "/api/v1/billing/webhooks/mock", json=mock_callback(first, status="failed")
    ).raise_for_status()
    second = start(client, inv, "stripe")
    assert first["id"] != second["id"]
    client.post(
        "/api/v1/billing/webhooks/mock", json=mock_callback(first, status="failed")
    ).raise_for_status()
    assert service.repository.latest_session(inv["id"]).id == second["id"]
    assert (
        client.post("/api/v1/billing/webhooks/mock", json=mock_callback(second)).json()[
            "status"
        ]
        == "paid"
    )


def test_pending_method_switch_is_rejected(client):
    inv = invoice(client)
    start(client, inv)
    assert (
        client.post(
            f"/api/v1/billing/invoices/{inv['id']}/pay", json={"method": "stripe"}
        ).status_code
        == 409
    )


def test_unknown_invoice_invalid_method_and_zero_fee(client):
    assert client.get("/api/v1/billing/invoices/missing").status_code == 404
    assert (
        client.post(
            "/api/v1/billing/invoices/missing/pay", json={"method": "payhere"}
        ).status_code
        == 404
    )
    inv = invoice(client, {**PAYLOAD, "exit_time": "2026-10-19T10:05:00+05:30"})
    assert (
        client.post(
            f"/api/v1/billing/invoices/{inv['id']}/pay", json={"method": "cash"}
        ).status_code
        == 422
    )
    session = start(client, inv)
    assert session["status"] == "paid" and session["provider"] == "free"
    assert session["amount_minor"] == 0


def payhere_callback(session, status="2", amount=None):
    fields = {
        "merchant_id": "1210000",
        "order_id": session["id"],
        "payhere_amount": amount or f"{session['amount_minor'] // 100}.00",
        "payhere_currency": "LKR",
        "status_code": status,
        "payment_id": "pay-001",
    }
    fields["md5sig"] = notification_hash(
        "1210000",
        session["id"],
        fields["payhere_amount"],
        "LKR",
        status,
        "sandbox-secret",
    )
    return fields


def test_payhere_sandbox_fields_and_verified_notification(client, service):
    service.settings = PaymentSettings(
        payhere_merchant_id="1210000",
        payhere_secret="sandbox-secret",
        public_base_url="https://sandbox.example.com",
    )
    inv = invoice(client)
    session = start(client, inv)
    assert session["checkout_url"] == "https://sandbox.payhere.lk/pay/checkout"
    assert session["checkout_fields"]["order_id"] == session["id"]
    assert "sandbox-secret" not in json.dumps(session)
    response = client.post(
        "/api/v1/billing/webhooks/payhere", data=payhere_callback(session)
    )
    assert response.status_code == 200 and response.json()["status"] == "paid"
    assert client.get("/api/v1/billing/payment-return").status_code == 200


def test_valid_payhere_signature_with_wrong_amount_cannot_settle(client, service):
    service.settings = PaymentSettings(
        payhere_merchant_id="1210000",
        payhere_secret="sandbox-secret",
        public_base_url="https://sandbox.example.com",
    )
    inv = invoice(client)
    session = start(client, inv)
    response = client.post(
        "/api/v1/billing/webhooks/payhere",
        data=payhere_callback(session, amount="1.00"),
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "PAYMENT_MISMATCH"
    assert (
        client.get(f"/api/v1/billing/invoices/{inv['id']}").json()["status"]
        == "pending"
    )


def stripe_signature(payload, timestamp=None):
    ts = timestamp if timestamp is not None else int(time.time())
    value = hmac.new(
        b"whsec_demo", f"{ts}.".encode() + payload, hashlib.sha256
    ).hexdigest()
    return f"t={ts},v1={value}"


def stripe_event(session, **changes):
    return {
        "id": "evt_demo",
        "object": "event",
        "type": "payment_intent.succeeded",
        "livemode": False,
        "data": {
            "object": {
                "id": session["provider_payment_id"],
                "object": "payment_intent",
                "status": "succeeded",
                "amount": session["amount_minor"],
                "amount_received": session["amount_minor"],
                "currency": session["currency"].lower(),
                "metadata": {
                    "session_id": session["id"],
                    "invoice_id": session["invoice_id"],
                },
            }
        },
        **changes,
    }


def stripe_session(client, service, monkeypatch, currency="lkr"):
    service.settings = PaymentSettings(
        stripe_key="sk_test_demo",
        stripe_webhook_secret="whsec_demo",
        stripe_currency=currency,
        usd_per_lkr=Decimal("0.0033") if currency == "usd" else None,
    )
    calls = []

    def create(**kwargs):
        calls.append(kwargs)
        return stripe.StripeObject.construct_from(
            {"id": "pi_demo", "client_secret": "pi_demo_secret_test"}, "sk_test_demo"
        )

    monkeypatch.setattr(stripe.PaymentIntent, "create", create)
    session = start(client, invoice(client), "stripe")
    assert calls[0]["metadata"]["session_id"] == session["id"]
    assert calls[0]["amount"] == session["amount_minor"]
    return session


def test_stripe_intent_and_real_sdk_signature_verification(
    client, service, monkeypatch
):
    session = stripe_session(client, service, monkeypatch)
    assert session["provider"] == "stripe" and session["status"] == "pending"
    body = json.dumps(stripe_event(session)).encode()
    response = client.post(
        "/api/v1/billing/webhooks/stripe",
        content=body,
        headers={"stripe-signature": stripe_signature(body)},
    )
    assert response.status_code == 200 and response.json()["status"] == "paid"


@pytest.mark.parametrize(
    "variant",
    ["bad_signature", "old_timestamp", "wrong_amount", "live_event", "wrong_intent"],
)
def test_stripe_invalid_or_mismatched_events(client, service, monkeypatch, variant):
    session = stripe_session(client, service, monkeypatch)
    event = stripe_event(session)
    if variant == "wrong_amount":
        event["data"]["object"]["amount_received"] = 1
    elif variant == "live_event":
        event["livemode"] = True
    elif variant == "wrong_intent":
        event["data"]["object"]["id"] = "pi_other"
    body = json.dumps(event).encode()
    signature = stripe_signature(
        body, int(time.time()) - 1000 if variant == "old_timestamp" else None
    )
    if variant == "bad_signature":
        signature = "t=1,v1=bad"
    response = client.post(
        "/api/v1/billing/webhooks/stripe",
        content=body,
        headers={"stripe-signature": signature},
    )
    assert response.status_code == 400
    assert (
        client.get(f"/api/v1/billing/invoices/{session['invoice_id']}").json()["status"]
        == "pending"
    )


def test_explicit_usd_conversion_retains_lkr_invoice(client, service, monkeypatch):
    session = stripe_session(client, service, monkeypatch, currency="usd")
    assert session["currency"] == "USD" and session["amount_minor"] == 33
    inv = client.get(f"/api/v1/billing/invoices/{session['invoice_id']}").json()
    assert inv["quote"]["total"] == 100 and inv["quote"]["currency"] == "LKR"


def test_live_key_and_missing_public_payhere_url_fail_clearly(client, service):
    inv = invoice(client)
    service.settings = PaymentSettings(stripe_key="sk_live_forbidden")
    assert (
        client.post(
            f"/api/v1/billing/invoices/{inv['id']}/pay", json={"method": "stripe"}
        ).status_code
        == 503
    )
    service.settings = PaymentSettings(
        payhere_merchant_id="1210000", payhere_secret="sandbox-secret"
    )
    assert (
        client.post(
            f"/api/v1/billing/invoices/{inv['id']}/pay", json={"method": "payhere"}
        ).status_code
        == 503
    )


def test_stripe_currency_rejection_uses_only_configured_usd_fallback(
    client, service, monkeypatch
):
    service.settings = PaymentSettings(
        stripe_key="sk_test_demo",
        stripe_webhook_secret="whsec_demo",
        usd_per_lkr=Decimal("0.0033"),
    )
    calls = []

    def create(**kwargs):
        calls.append(kwargs)
        if kwargs["currency"] == "lkr":
            raise stripe.InvalidRequestError("Unsupported account currency", "currency")
        return stripe.StripeObject.construct_from(
            {"id": "pi_demo", "client_secret": "pi_demo_secret_test"}, "sk_test_demo"
        )

    monkeypatch.setattr(stripe.PaymentIntent, "create", create)
    session = start(client, invoice(client), "stripe")
    assert [call["currency"] for call in calls] == ["lkr", "usd"]
    assert session["currency"] == "USD" and session["amount_minor"] == 33
    assert calls[0]["idempotency_key"] != calls[1]["idempotency_key"]


def test_stripe_api_failure_never_silently_confirms_or_mock_falls_back(
    client, service, monkeypatch
):
    service.settings = PaymentSettings(
        stripe_key="sk_test_demo", stripe_webhook_secret="whsec_demo"
    )

    def failed(**kwargs):
        raise stripe.APIConnectionError("No connection")

    monkeypatch.setattr(stripe.PaymentIntent, "create", failed)
    inv = invoice(client)
    response = client.post(
        f"/api/v1/billing/invoices/{inv['id']}/pay", json={"method": "stripe"}
    )
    assert response.status_code == 502
    assert response.json()["error"]["code"] == "PROVIDER_ERROR"
    assert (
        client.get(f"/api/v1/billing/invoices/{inv['id']}").json()["status"]
        == "pending"
    )


def test_stripe_failure_event_and_unrelated_events(client, service, monkeypatch):
    session = stripe_session(client, service, monkeypatch)
    ignored = json.dumps(
        {"id": "evt_ignore", "type": "customer.created", "livemode": False}
    ).encode()
    assert (
        client.post(
            "/api/v1/billing/webhooks/stripe",
            content=ignored,
            headers={"stripe-signature": stripe_signature(ignored)},
        ).json()["ignored"]
        is True
    )
    event = stripe_event(session, type="payment_intent.payment_failed")
    event["data"]["object"]["status"] = "requires_payment_method"
    event["data"]["object"]["amount_received"] = 0
    body = json.dumps(event).encode()
    response = client.post(
        "/api/v1/billing/webhooks/stripe",
        content=body,
        headers={"stripe-signature": stripe_signature(body)},
    )
    assert response.status_code == 200 and response.json()["status"] == "failed"


def test_unsigned_real_provider_callbacks_cannot_confirm_mock_session(client):
    session = start(client, invoice(client))
    assert (
        client.post(
            "/api/v1/billing/webhooks/stripe", json=mock_callback(session)
        ).status_code
        == 503
    )
    assert (
        client.post(
            "/api/v1/billing/webhooks/payhere", data=payhere_callback(session)
        ).status_code
        == 503
    )
    assert (
        client.get(f"/api/v1/billing/invoices/{session['invoice_id']}").json()["status"]
        == "pending"
    )

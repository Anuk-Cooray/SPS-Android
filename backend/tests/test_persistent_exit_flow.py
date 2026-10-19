"""Exercise restart, rollback and competing gate requests against actual SQLite."""

import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from test_payment_routes import invoice, mock_callback, start

from app.core.config import PaymentSettings
from app.main import app
from app.repositories.sqlite_invoice_repository import SqliteInvoiceRepository
from app.services.exit_token_service import ExitTokenService
from app.services.invoice_service import InvoiceService, get_invoice_service
from app.services.payments.base import PaymentError, WebhookRequest


def setup_payment(path, monkeypatch):
    repo = SqliteInvoiceRepository(path)
    service = InvoiceService(repo, PaymentSettings())
    monkeypatch.setenv("DEBUG", "true")
    app.dependency_overrides[get_invoice_service] = lambda: service
    try:
        with TestClient(app) as client:
            inv = invoice(client)
            session = start(client, inv)
            assert (
                client.get(
                    f"/api/v1/billing/invoices/{inv['id']}/exit-token"
                ).status_code
                == 403
            )
            assert (
                client.get("/api/v1/billing/bookings/BK-PAYMENT/invoice").json()["id"]
                == inv["id"]
            )
            assert (
                client.get("/api/v1/billing/bookings/missing/invoice").status_code
                == 404
            )
    finally:
        app.dependency_overrides.pop(get_invoice_service, None)
    return repo, service, inv, session


def test_restart_settlement_and_single_use_pass(tmp_path, monkeypatch):
    path = tmp_path / "billing.db"
    repo, _, inv, session = setup_payment(path, monkeypatch)
    repo.close()
    repo = SqliteInvoiceRepository(path)
    service = InvoiceService(repo, PaymentSettings())
    try:
        callback = WebhookRequest(json.dumps(mock_callback(session)).encode(), {})
        stored = service.get_invoice(inv["id"])
        assert service.create_invoice(stored.booking_id, stored.quote).id == inv["id"]
        assert service.start_payment(inv["id"], "payhere").id == session["id"]
        assert service.handle_webhook("mock", callback)["status"] == "paid"
        assert service.handle_webhook("mock", callback)["duplicate"]
        now = datetime.now(timezone.utc)
        tokens = ExitTokenService(repo, now=lambda: now)
        token = tokens.issue(inv["id"])
        assert tokens.issue(inv["id"]) == token
        with pytest.raises(PaymentError, match="Invalid exit pass"):
            tokens.consume(token.token + "bad")
        repo.close()
        repo = SqliteInvoiceRepository(path)
        tokens = ExitTokenService(repo)
        assert tokens.issue(inv["id"]) == token
        assert tokens.consume(token.token)["accepted"]
        with pytest.raises(PaymentError, match="already used"):
            tokens.consume(token.token)
        with pytest.raises(PaymentError, match="already used"):
            tokens.issue(inv["id"])
    finally:
        repo.close()


def test_expiry_renewal_and_barrier_auth(tmp_path, monkeypatch):
    repo, service, inv, session = setup_payment(tmp_path / "billing.db", monkeypatch)
    try:
        service.handle_webhook(
            "mock", WebhookRequest(json.dumps(mock_callback(session)).encode(), {})
        )
        now = datetime.now(timezone.utc)
        token = ExitTokenService(repo, now=lambda: now).issue(inv["id"])
        later = ExitTokenService(repo, now=lambda: now + timedelta(minutes=6))
        with pytest.raises(PaymentError, match="expired"):
            later.consume(token.token)
        renewed = later.issue(inv["id"])
        assert renewed.token != token.token
        with pytest.raises(PaymentError, match="replaced"):
            later.consume(token.token)
        app.dependency_overrides[get_invoice_service] = lambda: service
        monkeypatch.setenv("BARRIER_INTEGRATION_KEY", "test-barrier-key")
        with TestClient(app) as client:
            route = "/api/v1/billing/exit-tokens/consume"
            assert client.post(route, json={"token": token.token}).status_code == 403
            assert (
                client.post(
                    route,
                    json={"token": token.token},
                    headers={"X-Barrier-Key": "wrong"},
                ).status_code
                == 403
            )
            assert (
                client.post(
                    route,
                    json={"token": renewed.token},
                    headers={"X-Barrier-Key": "test-barrier-key"},
                ).status_code
                == 200
            )
    finally:
        app.dependency_overrides.pop(get_invoice_service, None)
        repo.close()


def test_rollback_and_competing_consumers(tmp_path, monkeypatch):
    path = tmp_path / "billing.db"
    repo, service, inv, session = setup_payment(path, monkeypatch)
    other = SqliteInvoiceRepository(path)
    try:
        with pytest.raises(RuntimeError):
            with repo.transaction():
                repo.remember_event("test", "rolled-back")
                raise RuntimeError("simulate interrupted workflow")
        assert not other.event_seen("test", "rolled-back")
        service.handle_webhook(
            "mock", WebhookRequest(json.dumps(mock_callback(session)).encode(), {})
        )
        token = ExitTokenService(repo).issue(inv["id"])

        def consume(repository):
            try:
                return ExitTokenService(repository).consume(token.token)["accepted"]
            except PaymentError as error:
                return error.code

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(consume, [repo, other]))
        assert results.count(True) == 1
        assert results.count("EXIT_TOKEN_USED") == 1
    finally:
        repo.close()
        other.close()


@pytest.mark.parametrize("token", ["garbage", "a.b.c", "%%%25.bad", "e30.bad", "."])
def test_malformed_exit_pass_is_rejected(tmp_path, token):
    repo = SqliteInvoiceRepository(tmp_path / "billing.db")
    try:
        with pytest.raises(PaymentError) as error:
            ExitTokenService(repo).consume(token)
        assert error.value.code == "INVALID_EXIT_TOKEN"
    finally:
        repo.close()

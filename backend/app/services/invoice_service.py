"""Invoice transitions and verified settlement, independent of HTTP handlers."""

import hmac
import os
from functools import lru_cache
from pathlib import Path
from threading import RLock
from uuid import uuid4

from app.core.config import PaymentSettings
from app.repositories.invoice_repository import (
    InvoiceRepository,
)
from app.repositories.sqlite_invoice_repository import SqliteInvoiceRepository
from app.schemas.billing import FeeQuote, Invoice, PaymentSession
from app.services.payments.base import PaymentError, PaymentProvider, WebhookRequest
from app.services.payments.mock_provider import MockProvider
from app.services.payments.payhere import PayHereProvider
from app.services.payments.stripe_provider import StripeProvider


class InvoiceService:
    def __init__(
        self, repository: InvoiceRepository, settings: PaymentSettings
    ) -> None:
        self.repository, self.settings = repository, settings
        self._mock = MockProvider()
        self._providers: dict[str, PaymentProvider] = {}
        self._lock = RLock()

    def remember_quote(self, quote: FeeQuote) -> None:
        with self._lock, self.repository.transaction():
            self.repository.remember_quote(quote)

    def create_invoice(self, booking_id: str, quote: FeeQuote) -> Invoice:
        with self._lock, self.repository.transaction():
            if quote.booking_id != booking_id or not self.repository.issued_quote(
                quote
            ):
                raise PaymentError(
                    "INVALID_QUOTE",
                    "Use an unchanged quote issued by this server for this booking",
                    422,
                )
            existing = self.repository.find_booking_invoice(booking_id)
            if existing:
                if existing.quote == quote:
                    return existing
                raise PaymentError(
                    "INVOICE_EXISTS",
                    "This booking already has an invoice; amendments require a later workflow",
                    409,
                )
            invoice = Invoice(
                id="inv-" + uuid4().hex, booking_id=booking_id, quote=quote
            )
            self.repository.save_invoice(invoice)
            return invoice

    def get_invoice(self, invoice_id: str) -> Invoice:
        invoice = self.repository.get_invoice(invoice_id)
        if invoice is None:
            raise PaymentError("INVOICE_NOT_FOUND", "Invoice not found", 404)
        return invoice

    def _provider(self, method: str) -> PaymentProvider:
        if method in self._providers:
            return self._providers[method]
        settings = self.settings
        if (
            method == "payhere"
            and settings.payhere_merchant_id
            and settings.payhere_secret
        ):
            if not settings.public_base_url.startswith("https://"):
                raise PaymentError(
                    "PAYMENT_CONFIG",
                    "PayHere sandbox requires PUBLIC_BASE_URL with a public HTTPS tunnel",
                    503,
                )
            provider = PayHereProvider(
                settings.payhere_merchant_id,
                settings.payhere_secret,
                settings.public_base_url,
            )
        elif method == "stripe" and settings.stripe_key:
            if not settings.stripe_key.startswith("sk_test_"):
                raise PaymentError(
                    "PAYMENT_CONFIG", "Only Stripe test keys are allowed", 503
                )
            if not settings.stripe_webhook_secret:
                return self._mock
            provider = StripeProvider(
                settings.stripe_key,
                settings.stripe_webhook_secret,
                settings.stripe_currency,
                settings.usd_per_lkr,
            )
        else:
            return self._mock
        self._providers[method] = provider
        return provider

    def start_payment(self, invoice_id: str, method: str) -> PaymentSession:
        if method not in {"payhere", "stripe", "guard"}:
            raise PaymentError("INVALID_METHOD", "Unsupported payment method", 422)
        with self._lock, self.repository.transaction():
            invoice = self.get_invoice(invoice_id)
            previous = self.repository.latest_session(invoice_id)
            if invoice.status == "paid":
                if previous:
                    return previous
                raise PaymentError("ALREADY_PAID", "Invoice already paid", 409)
            if previous and previous.status == "pending":
                if previous.method == method:
                    return previous  # Repeated taps do not create a second checkout.
                raise PaymentError(
                    "PAYMENT_PENDING",
                    "Finish the existing checkout before changing method",
                    409,
                )
            if previous and previous.status == "awaiting_guard" and method == "guard":
                return previous
            if invoice.quote.total == 0:
                session = PaymentSession(
                    id="free-" + uuid4().hex,
                    invoice_id=invoice.id,
                    method=method,
                    provider="free",
                    status="paid",
                    is_mock=False,
                    amount_minor=0,
                    currency="LKR",
                    message="No payment needed: zero-fee invoice settled.",
                )
            elif method == "guard":
                session = PaymentSession(
                    id="guard-" + uuid4().hex,
                    invoice_id=invoice.id,
                    method="guard",
                    provider="guard",
                    status="awaiting_guard",
                    is_mock=False,
                    amount_minor=invoice.quote.total * 100,
                    currency="LKR",
                    message="Awaiting guard confirmation. Admin confirmation endpoint is a team integration TODO.",
                )
            else:
                provider = self._provider(method)
                session = (
                    provider.create_session(invoice, method=method)
                    if provider is self._mock
                    else provider.create_session(invoice)
                )
            self.repository.save_session(session)
            new_status = (
                "awaiting_guard"
                if method == "guard" and session.status != "paid"
                else session.status
            )
            self.repository.save_invoice(
                invoice.model_copy(update={"status": new_status})
            )
            return session

    def handle_webhook(self, provider_name: str, request: WebhookRequest) -> dict:
        with self._lock, self.repository.transaction():
            provider = (
                self._mock if provider_name == "mock" else self._provider(provider_name)
            )
            if provider_name != "mock" and provider is self._mock:
                raise PaymentError(
                    "PAYMENT_CONFIG",
                    "Sandbox webhook credentials are not configured",
                    503,
                )
            event = provider.verify_webhook(request)
            if event is None:
                return {"received": True, "ignored": True}
            session = self.repository.get_session(event.session_id)
            if session is None:
                raise PaymentError(
                    "SESSION_NOT_FOUND", "Payment session not found", 404
                )
            if provider_name == "mock" and (
                not session.mock_webhook_token
                or not hmac.compare_digest(
                    session.mock_webhook_token.encode(),
                    (event.confirmation_token or "").encode(),
                )
            ):
                raise PaymentError("INVALID_WEBHOOK", "Invalid mock confirmation token")
            if (
                session.provider != provider_name
                or session.provider_payment_id != event.provider_payment_id
                or session.amount_minor != event.amount_minor
                or session.currency != event.currency
                or (
                    event.invoice_id is not None
                    and event.invoice_id != session.invoice_id
                )
            ):
                raise PaymentError(
                    "PAYMENT_MISMATCH",
                    "Verified callback does not match the recorded checkout",
                    400,
                )
            invoice = self.get_invoice(session.invoice_id)
            if self.repository.event_seen(provider_name, event.event_id):
                return {"received": True, "duplicate": True, "status": invoice.status}
            # A late failure cannot revoke paid settlement or regress a failed attempt to pending.
            new_session_status = session.status
            if session.status != "paid" and not (
                session.status == "failed" and event.status == "pending"
            ):
                new_session_status = event.status
            self.repository.save_session(
                session.model_copy(update={"status": new_session_status})
            )
            if invoice.status != "paid":
                if event.status == "paid":
                    invoice = invoice.model_copy(update={"status": "paid"})
                elif self.repository.latest_session(invoice.id).id == session.id:
                    invoice = invoice.model_copy(update={"status": new_session_status})
                self.repository.save_invoice(invoice)
            self.repository.remember_event(provider_name, event.event_id)
            return {"received": True, "status": invoice.status}


@lru_cache(maxsize=1)
def get_invoice_service() -> InvoiceService:
    settings = PaymentSettings.from_env()
    default = Path(__file__).resolve().parents[2] / ".data" / "billing.sqlite3"
    path = Path(os.getenv("BILLING_DB_PATH", str(default)))
    return InvoiceService(SqliteInvoiceRepository(path), settings)

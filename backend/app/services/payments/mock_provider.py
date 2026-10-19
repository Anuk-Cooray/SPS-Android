"""Explicit local simulation, never accepted by real provider webhook routes."""

import json
import secrets
from uuid import uuid4

from app.schemas.billing import Invoice, PaymentSession
from app.services.payments.base import (
    PaymentError,
    PaymentProvider,
    VerifiedPayment,
    WebhookRequest,
)


class MockProvider(PaymentProvider):
    def create_session(
        self, invoice: Invoice, method: str = "payhere"
    ) -> PaymentSession:
        session_id = "mock-" + uuid4().hex
        return PaymentSession(
            id=session_id,
            invoice_id=invoice.id,
            method=method,
            provider="mock",
            status="pending",
            is_mock=True,
            amount_minor=invoice.quote.total * 100,
            currency="LKR",
            provider_payment_id=session_id,
            mock_webhook_token=secrets.token_urlsafe(32),
            message="MOCK ONLY: no funds charged. Confirm through the DEBUG-only mock webhook.",
        )

    def verify_webhook(self, request: WebhookRequest) -> VerifiedPayment:
        try:
            data = json.loads(request.body)
            invoice_id, session_id, token = (
                data[name] for name in ("invoice_id", "session_id", "token")
            )
            if not all(
                isinstance(value, str) for value in (invoice_id, session_id, token)
            ):
                raise ValueError("Expected strings")
            if data["status"] not in {"paid", "failed"}:
                raise ValueError("Invalid status")
            if type(data["amount_minor"]) is not int or data["amount_minor"] < 0:
                raise ValueError("Expected integer minor units")
            return VerifiedPayment(
                event_id=f"{session_id}:{data['status']}",
                session_id=session_id,
                provider_payment_id=session_id,
                invoice_id=invoice_id,
                amount_minor=data["amount_minor"],
                currency=data["currency"],
                status=data["status"],
                confirmation_token=token,
            )
        except (ValueError, KeyError, TypeError) as error:
            raise PaymentError(
                "INVALID_WEBHOOK", "Invalid mock callback or confirmation token"
            ) from error

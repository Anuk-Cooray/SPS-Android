"""Stripe test mode only; monetary values passed to Stripe are integer minor units."""

from decimal import ROUND_HALF_UP, Decimal
from uuid import uuid4

import stripe

from app.schemas.billing import Invoice, PaymentSession
from app.services.payments.base import (
    PaymentError,
    PaymentProvider,
    VerifiedPayment,
    WebhookRequest,
)


class StripeProvider(PaymentProvider):
    def __init__(
        self,
        key: str,
        webhook_secret: str,
        currency: str = "lkr",
        usd_per_lkr: Decimal | None = None,
    ) -> None:
        if not key.startswith("sk_test_"):
            raise PaymentError(
                "PAYMENT_CONFIG", "Only Stripe sk_test_ keys are allowed", 503
            )
        if currency not in {"lkr", "usd"}:
            raise PaymentError(
                "PAYMENT_CONFIG", "Stripe demo currency must be lkr or usd", 503
            )
        if usd_per_lkr is not None and (
            not usd_per_lkr.is_finite() or usd_per_lkr <= 0
        ):
            raise PaymentError(
                "PAYMENT_CONFIG", "USD conversion rate must be positive and finite", 503
            )
        self.key, self.webhook_secret = key, webhook_secret
        self.currency, self.usd_per_lkr = currency, usd_per_lkr

    def _amount(self, total: int, currency: str) -> int:
        if currency == "lkr":
            return total * 100
        if self.usd_per_lkr is None:
            raise PaymentError(
                "PAYMENT_CONFIG",
                "USD sandbox fallback requires STRIPE_USD_PER_LKR; no exchange rate is guessed",
                503,
            )
        return int(
            (Decimal(total) * self.usd_per_lkr * 100).quantize(
                Decimal(1), rounding=ROUND_HALF_UP
            )
        )

    def create_session(self, invoice: Invoice) -> PaymentSession:
        session_id = "st-" + uuid4().hex
        currency = self.currency

        def create(selected: str):
            return stripe.PaymentIntent.create(
                api_key=self.key,
                amount=self._amount(invoice.quote.total, selected),
                currency=selected,
                metadata={"invoice_id": invoice.id, "session_id": session_id},
                automatic_payment_methods={"enabled": True},
                idempotency_key=session_id + "-" + selected,
            )

        try:
            try:
                intent = create(currency)
            except stripe.InvalidRequestError as error:
                # Only currency rejection permits a retry; other provider errors surface.
                if (
                    currency != "lkr"
                    or error.param != "currency"
                    or self.usd_per_lkr is None
                ):
                    raise
                currency = "usd"
                intent = create(currency)
        except stripe.StripeError as error:
            raise PaymentError(
                "PROVIDER_ERROR",
                "Stripe test session failed; check account currency support and test configuration",
                502,
            ) from error
        return PaymentSession(
            id=session_id,
            invoice_id=invoice.id,
            method="stripe",
            provider="stripe",
            status="pending",
            is_mock=False,
            amount_minor=self._amount(invoice.quote.total, currency),
            currency=currency.upper(),
            provider_payment_id=intent.id,
            client_secret=intent.client_secret,
            message="Stripe TEST PaymentIntent: complete with a test client; await signed webhook."
            + (
                " Explicit configured USD conversion used; invoice remains LKR."
                if currency == "usd"
                else ""
            ),
        )

    def verify_webhook(self, request: WebhookRequest) -> VerifiedPayment | None:
        try:
            event = stripe.Webhook.construct_event(
                request.body,
                request.headers.get("stripe-signature", ""),
                self.webhook_secret,
            )
            if event["livemode"] is not False:
                raise ValueError("Only test events allowed")
            statuses = {
                "payment_intent.succeeded": "paid",
                "payment_intent.payment_failed": "failed",
                "payment_intent.canceled": "failed",
            }
            if event["type"] not in statuses:
                return None
            intent = event["data"]["object"]
            status = statuses[event["type"]]
            if status == "paid" and intent["status"] != "succeeded":
                raise ValueError("Inconsistent success event")
            amount = intent["amount_received"] if status == "paid" else intent["amount"]
            if type(amount) is not int or amount < 0:
                raise ValueError("Invalid minor-unit amount")
            return VerifiedPayment(
                event_id=event["id"],
                session_id=intent["metadata"]["session_id"],
                invoice_id=intent["metadata"]["invoice_id"],
                provider_payment_id=intent["id"],
                amount_minor=amount,
                currency=intent["currency"].upper(),
                status=status,
            )
        except (
            stripe.SignatureVerificationError,
            ValueError,
            KeyError,
            TypeError,
            AttributeError,
        ) as error:
            raise PaymentError(
                "INVALID_WEBHOOK", "Invalid Stripe test signature or event fields"
            ) from error

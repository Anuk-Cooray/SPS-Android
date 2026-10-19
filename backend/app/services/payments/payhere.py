import hashlib
import hmac
from decimal import Decimal, InvalidOperation
from urllib.parse import parse_qs
from uuid import uuid4

from app.schemas.billing import Invoice, PaymentSession
from app.services.payments.base import (
    PaymentError,
    PaymentProvider,
    VerifiedPayment,
    WebhookRequest,
)


def md5_upper(value: str) -> str:
    # Required by the PayHere protocol; not used for passwords or our own tokens.
    return hashlib.md5(value.encode(), usedforsecurity=False).hexdigest().upper()


def checkout_hash(
    merchant_id: str, order_id: str, amount_2dp: str, currency: str, secret: str
) -> str:
    return md5_upper(merchant_id + order_id + amount_2dp + currency + md5_upper(secret))


def notification_hash(
    merchant_id: str,
    order_id: str,
    amount: str,
    currency: str,
    status: str,
    secret: str,
) -> str:
    return md5_upper(
        merchant_id + order_id + amount + currency + status + md5_upper(secret)
    )


class PayHereProvider(PaymentProvider):
    def __init__(self, merchant_id: str, secret: str, public_base_url: str) -> None:
        self.merchant_id, self.secret = merchant_id, secret
        self.base = public_base_url.rstrip("/")

    def create_session(self, invoice: Invoice) -> PaymentSession:
        session_id = "ph-" + uuid4().hex
        amount = f"{invoice.quote.total}.00"
        fields = {
            "merchant_id": self.merchant_id,
            "order_id": session_id,
            "amount": amount,
            "currency": "LKR",
            "items": f"Sandbox parking {invoice.id}",
            "return_url": self.base + "/api/v1/billing/payment-return",
            "cancel_url": self.base + "/api/v1/billing/payment-return",
            "notify_url": self.base + "/api/v1/billing/webhooks/payhere",
            "first_name": "Sandbox",
            "last_name": "Student",
            "email": "student@example.com",
            "phone": "0771234567",
            "address": "Sandbox campus",
            "city": "Malabe",
            "country": "Sri Lanka",
        }
        fields["hash"] = checkout_hash(
            self.merchant_id, session_id, amount, "LKR", self.secret
        )
        return PaymentSession(
            id=session_id,
            invoice_id=invoice.id,
            method="payhere",
            provider="payhere",
            status="pending",
            is_mock=False,
            amount_minor=invoice.quote.total * 100,
            currency="LKR",
            provider_payment_id=session_id,
            checkout_url="https://sandbox.payhere.lk/pay/checkout",
            checkout_fields=fields,
            message="PayHere SANDBOX: submit checkout_fields as an HTML form POST; await verified notification.",
        )

    def verify_webhook(self, request: WebhookRequest) -> VerifiedPayment:
        try:
            if (
                request.headers.get("content-type", "").split(";")[0].strip().lower()
                != "application/x-www-form-urlencoded"
            ):
                raise ValueError("Expected form encoding")
            values = parse_qs(request.body.decode("utf-8"), keep_blank_values=True)
            names = (
                "merchant_id",
                "order_id",
                "payhere_amount",
                "payhere_currency",
                "status_code",
                "md5sig",
                "payment_id",
            )
            if any(
                len(values.get(name, [])) != 1 or not values[name][0] for name in names
            ):
                raise ValueError("Missing or duplicate callback fields")
            data = {name: values[name][0] for name in names}
            expected = notification_hash(
                data["merchant_id"],
                data["order_id"],
                data["payhere_amount"],
                data["payhere_currency"],
                data["status_code"],
                self.secret,
            )
            if data["merchant_id"] != self.merchant_id or not hmac.compare_digest(
                expected, data["md5sig"]
            ):
                raise ValueError("Invalid signature/merchant")
            amount = Decimal(data["payhere_amount"]) * 100
            if (
                not amount.is_finite()
                or amount < 0
                or amount != amount.to_integral_value()
            ):
                raise ValueError("Invalid amount")
            statuses = {"2": "paid", "0": "pending", "-1": "failed", "-2": "failed"}
            if data["status_code"] not in statuses:
                # Chargebacks/refunds require a separate post-payment ledger later.
                raise ValueError("Unsupported payment status")
            return VerifiedPayment(
                event_id=f"{data['payment_id']}:{data['status_code']}",
                session_id=data["order_id"],
                provider_payment_id=data["order_id"],
                amount_minor=int(amount),
                currency=data["payhere_currency"],
                status=statuses[data["status_code"]],
            )
        except (
            ValueError,
            TypeError,
            KeyError,
            UnicodeError,
            InvalidOperation,
        ) as error:
            raise PaymentError(
                "INVALID_WEBHOOK", "Invalid PayHere signature or callback fields"
            ) from error

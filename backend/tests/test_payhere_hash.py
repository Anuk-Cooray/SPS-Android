from urllib.parse import urlencode

import pytest

from app.services.payments.base import PaymentError, WebhookRequest
from app.services.payments.payhere import (
    PayHereProvider,
    checkout_hash,
    notification_hash,
)

MERCHANT = "1210000"
SECRET = "sandbox-secret"


def test_fixed_checkout_hash():
    # Local fixed vector, not a claim of official merchant credentials.
    assert (
        checkout_hash(MERCHANT, "PH-TEST-001", "250.00", "LKR", SECRET)
        == "A323A0E132222CD6C10F7A440DE67871"
    )


def test_fixed_notification_hash():
    assert (
        notification_hash(MERCHANT, "PH-TEST-001", "250.00", "LKR", "2", SECRET)
        == "CB3D5023FD3671EB1088115BE604027B"
    )


def callback(status="2"):
    fields = {
        "merchant_id": MERCHANT,
        "order_id": "PH-TEST-001",
        "payhere_amount": "250.00",
        "payhere_currency": "LKR",
        "status_code": status,
        "payment_id": "payment-001",
    }
    fields["md5sig"] = notification_hash(
        MERCHANT,
        fields["order_id"],
        fields["payhere_amount"],
        fields["payhere_currency"],
        status,
        SECRET,
    )
    return fields


@pytest.mark.parametrize(
    "status,expected",
    [("2", "paid"), ("0", "pending"), ("-1", "failed"), ("-2", "failed")],
)
def test_valid_statuses(status, expected):
    request = WebhookRequest(
        urlencode(callback(status)).encode(),
        {"content-type": "application/x-www-form-urlencoded"},
    )
    result = PayHereProvider(
        MERCHANT, SECRET, "https://sandbox.example.com"
    ).verify_webhook(request)
    assert result.status == expected
    assert result.amount_minor == 25000


@pytest.mark.parametrize(
    "field,value",
    [
        ("merchant_id", "wrong"),
        ("payhere_amount", "1.00"),
        ("payhere_currency", "USD"),
        ("md5sig", "wrong"),
    ],
)
def test_tampered_callback(field, value):
    fields = callback()
    fields[field] = value
    with pytest.raises(PaymentError, match="Invalid PayHere"):
        PayHereProvider(MERCHANT, SECRET, "https://sandbox.example.com").verify_webhook(
            WebhookRequest(
                urlencode(fields).encode(),
                {"content-type": "application/x-www-form-urlencoded"},
            )
        )


def test_duplicate_fields_and_json_rejected():
    provider = PayHereProvider(MERCHANT, SECRET, "https://sandbox.example.com")
    with pytest.raises(PaymentError):
        provider.verify_webhook(
            WebhookRequest(
                (urlencode(callback()) + "&status_code=2").encode(),
                {"content-type": "application/x-www-form-urlencoded"},
            )
        )
    with pytest.raises(PaymentError):
        provider.verify_webhook(
            WebhookRequest(b"{}", {"content-type": "application/json"})
        )


def test_non_ascii_signature_is_rejected():
    fields = callback()
    fields["md5sig"] = "invalid-☃"
    with pytest.raises(PaymentError):
        PayHereProvider(MERCHANT, SECRET, "https://sandbox.example.com").verify_webhook(
            WebhookRequest(
                urlencode(fields).encode(),
                {"content-type": "application/x-www-form-urlencoded"},
            )
        )

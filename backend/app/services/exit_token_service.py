"""Short-lived, single-use exit grants; gate hardware remains a team integration."""

import base64
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone

from app.repositories.invoice_repository import InvoiceRepository
from app.schemas.billing import ExitGrant, ExitToken
from app.services.payments.base import PaymentError


class ExitTokenService:
    def __init__(self, repository: InvoiceRepository, now=None):
        self.repository = repository
        self.now = now or (lambda: datetime.now(timezone.utc))

    def issue(self, invoice_id: str) -> ExitToken:
        with self.repository.transaction():
            invoice = self.repository.get_invoice(invoice_id)
            if invoice is None:
                raise PaymentError("INVOICE_NOT_FOUND", "Invoice not found", 404)
            if invoice.status != "paid":
                raise PaymentError("PAYMENT_REQUIRED", "Settle the invoice first", 403)
            previous = self.repository.latest_exit_grant(invoice_id)
            now = self.now()
            if previous and previous.used_at:
                raise PaymentError("EXIT_TOKEN_USED", "Exit pass already used", 409)
            if previous and previous.expires_at > now:
                return ExitToken(
                    invoice_id=invoice_id,
                    token=previous.token,
                    expires_at=previous.expires_at,
                )
            expires = (now + timedelta(minutes=5)).replace(microsecond=0)
            nonce = secrets.token_urlsafe(24)
            payload = json.dumps(
                {
                    "v": 1,
                    "invoice_id": invoice_id,
                    "booking_id": invoice.booking_id,
                    "nonce": nonce,
                    "exp": int(expires.timestamp()),
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
            encoded = base64.urlsafe_b64encode(payload).decode().rstrip("=")
            signature = hmac.new(
                self.repository.get_or_create_signing_key(),
                encoded.encode(),
                hashlib.sha256,
            ).hexdigest()
            token = f"{encoded}.{signature}"
            self.repository.save_exit_grant(
                ExitGrant(
                    nonce=nonce, invoice_id=invoice_id, token=token, expires_at=expires
                )
            )
            return ExitToken(invoice_id=invoice_id, token=token, expires_at=expires)

    def consume(self, token: str) -> dict:
        with self.repository.transaction():
            try:
                encoded, signature = token.split(".")
                expected = hmac.new(
                    self.repository.get_or_create_signing_key(),
                    encoded.encode(),
                    hashlib.sha256,
                ).hexdigest()
                if not hmac.compare_digest(signature, expected):
                    raise ValueError("signature")
                payload = json.loads(
                    base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
                )
                grant = self.repository.get_exit_grant(payload["nonce"])
                if not grant or grant.token != token or payload["v"] != 1:
                    raise ValueError("grant")
            except (ValueError, KeyError, TypeError, UnicodeError) as error:
                raise PaymentError(
                    "INVALID_EXIT_TOKEN", "Invalid exit pass", 400
                ) from error
            latest = self.repository.latest_exit_grant(grant.invoice_id)
            if latest is None or latest.nonce != grant.nonce:
                raise PaymentError(
                    "EXIT_TOKEN_SUPERSEDED",
                    "Exit pass replaced; use the latest pass",
                    409,
                )
            if grant.used_at:
                raise PaymentError("EXIT_TOKEN_USED", "Exit pass already used", 409)
            now = self.now()
            if grant.expires_at <= now:
                raise PaymentError(
                    "EXIT_TOKEN_EXPIRED", "Exit pass expired; request another", 410
                )
            invoice = self.repository.get_invoice(grant.invoice_id)
            if invoice is None or invoice.status != "paid":
                raise PaymentError("PAYMENT_REQUIRED", "Invoice is not paid", 403)
            self.repository.save_exit_grant(grant.model_copy(update={"used_at": now}))
            return {
                "accepted": True,
                "invoice_id": invoice.id,
                "booking_id": invoice.booking_id,
            }

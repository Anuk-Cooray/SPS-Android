from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Mapping

from app.schemas.billing import Invoice, PaymentSession


class PaymentError(Exception):
    def __init__(self, code: str, message: str, status: int = 400) -> None:
        self.code, self.message, self.status = code, message, status
        super().__init__(message)


@dataclass(frozen=True)
class WebhookRequest:
    body: bytes
    headers: Mapping[str, str]


@dataclass(frozen=True)
class VerifiedPayment:
    event_id: str
    session_id: str
    provider_payment_id: str
    amount_minor: int
    currency: str
    status: str
    invoice_id: str | None = None


class PaymentProvider(ABC):
    @abstractmethod
    def create_session(self, invoice: Invoice) -> PaymentSession: ...

    @abstractmethod
    def verify_webhook(self, request: WebhookRequest) -> VerifiedPayment | None: ...

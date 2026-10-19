"""Storage boundary for local SQLite and isolated in-memory test adapters."""

import secrets
from abc import ABC, abstractmethod
from collections.abc import Iterator
from contextlib import contextmanager
from hashlib import sha256
from threading import RLock

from app.schemas.billing import ExitGrant, FeeQuote, Invoice, PaymentSession


def quote_key(quote: FeeQuote) -> str:
    return sha256(quote.model_dump_json().encode()).hexdigest()


class InvoiceRepository(ABC):
    @contextmanager
    def transaction(self) -> Iterator[None]:
        """Memory storage uses the service lock; database adapters override this."""
        yield

    @abstractmethod
    def get_or_create_signing_key(self) -> bytes: ...

    @abstractmethod
    def save_exit_grant(self, grant: ExitGrant) -> None: ...

    @abstractmethod
    def get_exit_grant(self, nonce: str) -> ExitGrant | None: ...

    @abstractmethod
    def latest_exit_grant(self, invoice_id: str) -> ExitGrant | None: ...

    @abstractmethod
    def remember_quote(self, quote: FeeQuote) -> None: ...

    @abstractmethod
    def issued_quote(self, quote: FeeQuote) -> bool: ...

    @abstractmethod
    def save_invoice(self, invoice: Invoice) -> None: ...

    @abstractmethod
    def get_invoice(self, invoice_id: str) -> Invoice | None: ...

    @abstractmethod
    def find_booking_invoice(self, booking_id: str) -> Invoice | None: ...

    @abstractmethod
    def save_session(self, session: PaymentSession) -> None: ...

    @abstractmethod
    def get_session(self, session_id: str) -> PaymentSession | None: ...

    @abstractmethod
    def latest_session(self, invoice_id: str) -> PaymentSession | None: ...

    @abstractmethod
    def event_seen(self, provider: str, event_id: str) -> bool: ...

    @abstractmethod
    def remember_event(self, provider: str, event_id: str) -> None: ...


class InMemoryInvoiceRepository(InvoiceRepository):
    """Transaction lock for local services; not shared across API workers."""

    def __init__(self) -> None:
        self._lock = RLock()
        self._signing_key = secrets.token_bytes(32)
        self._grants: dict[str, ExitGrant] = {}
        self._quotes: set[str] = set()
        self._invoices: dict[str, Invoice] = {}
        self._bookings: dict[str, str] = {}
        self._sessions: dict[str, PaymentSession] = {}
        self._latest: dict[str, str] = {}
        self._events: set[tuple[str, str]] = set()

    @contextmanager
    def transaction(self) -> Iterator[None]:
        with self._lock:
            yield

    def remember_quote(self, quote: FeeQuote) -> None:
        self._quotes.add(quote_key(quote))

    def issued_quote(self, quote: FeeQuote) -> bool:
        return quote_key(quote) in self._quotes

    def save_invoice(self, invoice: Invoice) -> None:
        self._invoices[invoice.id] = invoice.model_copy(deep=True)
        self._bookings[invoice.booking_id] = invoice.id

    def get_invoice(self, invoice_id: str) -> Invoice | None:
        invoice = self._invoices.get(invoice_id)
        return invoice.model_copy(deep=True) if invoice else None

    def find_booking_invoice(self, booking_id: str) -> Invoice | None:
        return self.get_invoice(self._bookings.get(booking_id, ""))

    def save_session(self, session: PaymentSession) -> None:
        if session.id not in self._sessions:
            self._latest[session.invoice_id] = session.id
        self._sessions[session.id] = session.model_copy(deep=True)

    def get_session(self, session_id: str) -> PaymentSession | None:
        session = self._sessions.get(session_id)
        return session.model_copy(deep=True) if session else None

    def latest_session(self, invoice_id: str) -> PaymentSession | None:
        return self.get_session(self._latest.get(invoice_id, ""))

    def event_seen(self, provider: str, event_id: str) -> bool:
        return (provider, event_id) in self._events

    def remember_event(self, provider: str, event_id: str) -> None:
        self._events.add((provider, event_id))

    def get_or_create_signing_key(self) -> bytes:
        return self._signing_key

    def save_exit_grant(self, grant: ExitGrant) -> None:
        self._grants[grant.nonce] = grant.model_copy(deep=True)

    def get_exit_grant(self, nonce: str) -> ExitGrant | None:
        grant = self._grants.get(nonce)
        return grant.model_copy(deep=True) if grant else None

    def latest_exit_grant(self, invoice_id: str) -> ExitGrant | None:
        matches = [
            grant for grant in self._grants.values() if grant.invoice_id == invoice_id
        ]
        return matches[-1].model_copy(deep=True) if matches else None

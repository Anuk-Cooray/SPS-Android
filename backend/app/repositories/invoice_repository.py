"""Storage boundary; replace the memory implementation after the DB decision."""

from abc import ABC, abstractmethod
from hashlib import sha256

from app.schemas.billing import FeeQuote, Invoice, PaymentSession


def quote_key(quote: FeeQuote) -> str:
    return sha256(quote.model_dump_json().encode()).hexdigest()


class InvoiceRepository(ABC):
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
    """Accessed under InvoiceService's lock; not shared across API workers."""

    def __init__(self) -> None:
        self._quotes: set[str] = set()
        self._invoices: dict[str, Invoice] = {}
        self._bookings: dict[str, str] = {}
        self._sessions: dict[str, PaymentSession] = {}
        self._latest: dict[str, str] = {}
        self._events: set[tuple[str, str]] = set()

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

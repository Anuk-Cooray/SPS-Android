"""Local persistent adapter, not the team's final platform database choice."""

import secrets
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from threading import RLock

from app.repositories.invoice_repository import InvoiceRepository, quote_key
from app.schemas.billing import ExitGrant, FeeQuote, Invoice, PaymentSession


class SqliteInvoiceRepository(InvoiceRepository):
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = RLock()
        self._db = sqlite3.connect(path, timeout=15, check_same_thread=False)
        path.chmod(0o600)
        self._db.execute("PRAGMA foreign_keys = ON")
        self._db.execute("PRAGMA journal_mode = WAL")
        self._db.executescript("""
            CREATE TABLE IF NOT EXISTS quotes (hash TEXT PRIMARY KEY);
            CREATE TABLE IF NOT EXISTS invoices (
                id TEXT PRIMARY KEY, booking_id TEXT NOT NULL UNIQUE, data TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
                invoice_id TEXT NOT NULL REFERENCES invoices(id), data TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS events (
                provider TEXT NOT NULL, event_id TEXT NOT NULL,
                PRIMARY KEY (provider, event_id));
            CREATE TABLE IF NOT EXISTS signing_keys (name TEXT PRIMARY KEY, value BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS exit_grants (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, nonce TEXT NOT NULL UNIQUE,
                invoice_id TEXT NOT NULL REFERENCES invoices(id), data TEXT NOT NULL);
        """)
        self._db.commit()

    @contextmanager
    def transaction(self) -> Iterator[None]:
        # BEGIN IMMEDIATE serializes competing read-modify-write workflows, including
        # different API processes using the same local SQLite file.
        with self._lock:
            if self._db.in_transaction:
                yield
                return
            self._db.execute("BEGIN IMMEDIATE")
            try:
                yield
                self._db.commit()
            except BaseException:
                self._db.rollback()
                raise

    def close(self) -> None:
        with self._lock:
            self._db.close()

    def remember_quote(self, quote: FeeQuote) -> None:
        with self.transaction():
            self._db.execute(
                "INSERT OR IGNORE INTO quotes VALUES (?)", (quote_key(quote),)
            )

    def issued_quote(self, quote: FeeQuote) -> bool:
        with self._lock:
            return (
                self._db.execute(
                    "SELECT 1 FROM quotes WHERE hash=?", (quote_key(quote),)
                ).fetchone()
                is not None
            )

    def save_invoice(self, invoice: Invoice) -> None:
        with self.transaction():
            self._db.execute(
                """INSERT INTO invoices(id, booking_id, data) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET data=excluded.data""",
                (invoice.id, invoice.booking_id, invoice.model_dump_json()),
            )

    def get_invoice(self, invoice_id: str) -> Invoice | None:
        with self._lock:
            row = self._db.execute(
                "SELECT data FROM invoices WHERE id=?", (invoice_id,)
            ).fetchone()
            return Invoice.model_validate_json(row[0]) if row else None

    def find_booking_invoice(self, booking_id: str) -> Invoice | None:
        with self._lock:
            row = self._db.execute(
                "SELECT data FROM invoices WHERE booking_id=?", (booking_id,)
            ).fetchone()
            return Invoice.model_validate_json(row[0]) if row else None

    def save_session(self, session: PaymentSession) -> None:
        with self.transaction():
            # Updating a callback must not make an old session the newest attempt.
            self._db.execute(
                """INSERT INTO sessions(id, invoice_id, data) VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET data=excluded.data""",
                (session.id, session.invoice_id, session.model_dump_json()),
            )

    def get_session(self, session_id: str) -> PaymentSession | None:
        with self._lock:
            row = self._db.execute(
                "SELECT data FROM sessions WHERE id=?", (session_id,)
            ).fetchone()
            return PaymentSession.model_validate_json(row[0]) if row else None

    def latest_session(self, invoice_id: str) -> PaymentSession | None:
        with self._lock:
            row = self._db.execute(
                "SELECT data FROM sessions WHERE invoice_id=? ORDER BY sequence DESC LIMIT 1",
                (invoice_id,),
            ).fetchone()
            return PaymentSession.model_validate_json(row[0]) if row else None

    def event_seen(self, provider: str, event_id: str) -> bool:
        with self._lock:
            return (
                self._db.execute(
                    "SELECT 1 FROM events WHERE provider=? AND event_id=?",
                    (provider, event_id),
                ).fetchone()
                is not None
            )

    def remember_event(self, provider: str, event_id: str) -> None:
        with self.transaction():
            self._db.execute(
                "INSERT OR IGNORE INTO events VALUES (?, ?)", (provider, event_id)
            )

    def get_or_create_signing_key(self) -> bytes:
        with self.transaction():
            self._db.execute(
                "INSERT OR IGNORE INTO signing_keys VALUES ('exit_hmac', ?)",
                (secrets.token_bytes(32),),
            )
            return self._db.execute(
                "SELECT value FROM signing_keys WHERE name='exit_hmac'"
            ).fetchone()[0]

    def save_exit_grant(self, grant: ExitGrant) -> None:
        with self.transaction():
            self._db.execute(
                """INSERT INTO exit_grants(nonce, invoice_id, data) VALUES (?, ?, ?)
                ON CONFLICT(nonce) DO UPDATE SET data=excluded.data""",
                (grant.nonce, grant.invoice_id, grant.model_dump_json()),
            )

    def get_exit_grant(self, nonce: str) -> ExitGrant | None:
        with self._lock:
            row = self._db.execute(
                "SELECT data FROM exit_grants WHERE nonce=?", (nonce,)
            ).fetchone()
            return ExitGrant.model_validate_json(row[0]) if row else None

    def latest_exit_grant(self, invoice_id: str) -> ExitGrant | None:
        with self._lock:
            row = self._db.execute(
                "SELECT data FROM exit_grants WHERE invoice_id=? ORDER BY sequence DESC LIMIT 1",
                (invoice_id,),
            ).fetchone()
            return ExitGrant.model_validate_json(row[0]) if row else None

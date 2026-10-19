# Local invoice persistence

## Approach
`SqliteInvoiceRepository` implements the existing storage boundary with Python's
standard sqlite3 library. Quotes are registered by hash, booking IDs are unique,
and invoice/session payloads use Pydantic JSON. Callback updates preserve the
original attempt order. Transactions wrap the entire settlement workflow, so
invoice status and deduplication records commit together or roll back together.
`BEGIN IMMEDIATE` serializes writers across connections; a per-connection RLock
also protects FastAPI thread access. Mock callback tokens are random persisted
secrets compared against the recorded session, so they survive service restart.
The HTTP app discovers existing invoices by booking before requesting a new quote.

## Alternatives and limitations
Memory is convenient for isolated tests but loses payments on restart. PostgreSQL
would support a shared production service; MongoDB is another team option. SQLite
provides an inspectable local milestone without resolving that production choice.
The file is ignored and chmod 0600. Backups, migrations, encryption at rest,
retention and production ownership authentication are still needed. Provider
network creation currently occurs inside a write transaction; a production job
workflow should reduce lock time and reconcile interrupted external creation.

## Validation
Tests reopen the database before settling an existing mock session, preserve
callback deduplication, check rollback and race two independent connections.

## Three viva questions
- **Why persist payment attempts?** Verified callbacks must match the original
  provider, amount and currency even after a restart.
- **Why a transaction around settlement?** A crash must not save paid status
  without the corresponding callback ledger update.
- **Did SQLite settle the team's database decision?** No. It is a local adapter
  behind the same repository interface.

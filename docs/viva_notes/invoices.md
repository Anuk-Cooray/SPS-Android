# Invoice service and repository

## What it does / why
InvoiceService remembers the hash of each server-issued quote, rejects altered quotes or mismatched bookings, and creates one pending invoice per booking. An identical create retry reuses that invoice. InvoiceRepository is an abstract storage boundary; its in-memory implementation copies stored data, tracks checkout attempts and deduplicates provider events. A service lock serializes state changes in the single API process. A durable database can later replace memory after the team's stack decision.

## Payment transitions
Checkout creation remains pending. Repeated requests reuse a pending checkout; a conflicting digital method returns 409. Guard selection becomes awaiting_guard, and can switch to digital. Verified webhooks must match the stored session's provider, payment ID, amount and currency. Duplicates are acknowledged; a late failure cannot downgrade a paid invoice or reset which attempt is newest. Zero-fee invoices settle without charging. The checkout return page never settles invoices.

## Alternatives / limitations
No authentication, quote expiry, invoice amendment, persistent storage or cross-worker locking. Restart loses everything; use one worker. An issued quote proves provenance, not authorization or tariff freshness. If an old failed attempt later succeeds after a new attempt started, paid status is preserved, but duplicate external charges need reconciliation. Crash/timeout recovery requires durable payment-attempt storage; session reuse alone cannot solve an unknown provider outcome. Refunds and chargebacks are later ledger work. No teammate-owned dashboard or booking state was changed.

## Three viva questions
- **Why not accept any client quote?** A driver could replace the total; only an unchanged server-issued quote is eligible.
- **Why separate storage?** The billing workflow can remain the same when memory is replaced with the team's database choice.
- **Why is paid sticky?** A retried/late failure must not revoke a confirmed payment; reversals need an explicit ledger workflow.

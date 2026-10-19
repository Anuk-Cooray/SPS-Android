# Paid-only exit passes

## Approach
The server checks invoice settlement before issuing a five-minute pass. Compact
JSON binds version, invoice, booking, expiry and a random nonce. HMAC-SHA256 signs
its base64url representation using a persisted server key. The stored grant adds
revocation by replacement and single-use consumption. Validation, expiry check
and used-at write share one SQLite transaction. A separate barrier backend must
present a configured integration key; the mobile app never receives that key.
The app displays a paid QR before its explicit Finish demo exit callback. Its
offline alternative is labelled unsigned and cannot authorize a real gate.

## Alternatives and limitations
An opaque random reference with server lookup could also work; the signature
provides tamper evidence while storage still supplies replay protection. JWT
would add a dependency without eliminating single-use storage. This local shared
key design needs ownership authentication, key rotation, deployment controls and
an agreed retry protocol between token consumption and physical opening. The
endpoint does not operate hardware. Losing the SQLite file loses its signing key
and authorization ledger. Billing does not implement teammates' barrier component.

## Validation
Tests check unpaid rejection, signature tampering, expiry, renewal, restart,
replay, protected consumption and competing database consumers. Flutter verifies
that payment confirmation and explicit user completion are separate actions.

## Three viva questions
- **Why isn't signing enough?** A valid signature can be replayed; used-at storage
  enforces single use.
- **Why check paid status again during consumption?** Gate authorization must
  still correspond to a settled invoice.
- **Why not put the barrier key in Flutter?** A mobile secret can be extracted;
  consumption belongs to the trusted barrier backend.

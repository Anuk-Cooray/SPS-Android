# Sandbox payment adapters

## What it does / why
PaymentProvider defines create_session(invoice) and verify_webhook(request). Framework-independent request/event records keep parsing and verification outside route handlers. PayHere returns a sandbox HTML form POST payload, with a two-decimal LKR amount and server-generated upper-case MD5 protocol hash. Its form notification verifies the separate status-inclusive hash and merchant ID. The original signed amount text is preserved for hashing; settlement matches integer minor units. Only success code 2 settles; 0 waits, -1/-2 fail.

Stripe creates a test PaymentIntent with invoice/session metadata and a per-attempt idempotency key. Live keys/events are rejected. The SDK verifies the exact raw webhook body, signature and timestamp; success also checks actual amount_received. InvoiceService binds the event to the stored intent/session/amount/currency. Client secrets are returned for future test-client confirmation, not logged.

## Mock and currency choices
Missing credentials select an explicit pending mock session. A per-process random HMAC token binds the development callback to its invoice/session; DEBUG must be true. That token never authorizes real provider settlement. Guard has no confirmation endpoint yet. LKR is Stripe's default. USD needs an explicit positive configured conversion rate; only a currency-parameter rejection permits an automatic USD retry. Monetary conversion uses Decimal and integer cents, while invoices stay whole LKR. No exchange rate is guessed.

## Validation / limitations
PayHere protocol details were checked against its current developer documentation. Tests use fixed local hash vectors, tampered/form notifications, SDK-verified signed Stripe fixtures, and stubbed PaymentIntent creation. No real credentials or external sandbox checkout were run. PayHere contact fields are fictional sandbox samples. Client hosted checkout/Elements, guard confirmation, refunds, chargebacks and durable retry recovery remain future work. Standard provider adapters are appropriate; custom payment cryptography is unnecessary beyond the explicitly local mock token.

## Three viva questions
- **Why is a redirect insufficient?** Only a verified provider callback proves settlement for the recorded amount.
- **Why compare currency and payment ID too?** A valid signature for another checkout must not settle this invoice.
- **Why not automatically rename LKR to USD?** Currency conversion changes the amount; it requires an explicit rate and matching session ledger.

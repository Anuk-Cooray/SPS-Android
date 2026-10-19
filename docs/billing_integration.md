> Update: local SQLite persistence and paid-only exit-token issue/consume endpoints
> are implemented. See [the current contract](billing_50_percent.md). The future
> platform database and hardware integration remain team decisions.

# Component 4 integration hand-off

This is a contract proposal for the next increment, not a claim that analytics
endpoints or the admin UI already exist. Anuk's dashboard, Samudi's occupancy
service and Varunprasath's barrier service have not been edited.

## Available now

| Data | Current source | Meaning |
|---|---|---|
| booking_id, lot_id | Quote request / app Booking | Existing app identifiers; demo input, not authenticated ownership |
| invoice.id, booking_id, status | Invoice endpoints | pending / awaiting_guard / paid / failed |
| quote.entry_time, exit_time | Invoice quote | UTC instants; display/bucket in Asia/Colombo |
| quote.line_items, subtotal, surge_amount, total, currency | Invoice quote | Integer whole LKR; surge_amount also includes cap/rounding adjustments |
| session.method, provider, is_mock | Payment session | payhere / stripe / guard; sandbox and mock transactions must be labelled |
| session.amount_minor, currency | Backend session repository | Expected provider settlement; may be configured USD in Stripe test mode |
| ts, yhat, yhat_lower, yhat_upper, demand_level | Forecast endpoint | Synthetic occupancy fractions, not real campus measurements or calibrated intervals |

The frontend's current PaymentSession projection keeps only fields needed for
status display. Hosted payment client metadata can be added when that UI is built.
The billing API, not a displayed QR/redirect, is responsible for settlement status.

## Proposed admin analytics fields (future API)

| Metric | Proposed fields | Aggregation / caveat |
|---|---|---|
| Revenue by hour | lot_id, bucket_start_utc, revenue_lkr, paid_invoice_count, is_demo | Sum whole-LKR invoice totals by paid_at, only once per paid invoice; exclude failed/guard-pending invoices and separate mock/test revenue |
| Payment mix | lot_id, period_start_utc, method, count, revenue_lkr, is_demo | Confirmed invoice payments grouped by successful attempt's method; prevent retries counting twice |
| Average stay | lot_id, period_start_utc, completed_visits, average_stay_minutes | exit_time minus actual checkedInAt; define whether only completed visits are included |
| Forecast vs actual | lot_id, ts, forecast_demand, actual_occupancy, absolute_error, model_version, is_synthetic | Align hourly Colombo buckets, retain forecast issue time, and compare with observations available later |

Invoices currently do not persist lot_id; retain it on the invoice or join an
authoritative booking record before exposing per-lot analytics.

Required persistent additions before these metrics are authoritative: lot_id, paid_at,
confirmed attempt/method, settlement/event ledger, invoice amendments/refunds,
model version and forecast issue time. Actual occupancy comes from Samudi's
LotOccupancyService; the current synthetic CSV is only a pipeline placeholder.
Use UTC storage and Colombo display buckets; do not group by the phone's timezone.
Revenue excludes pending/failed invoices and requires an agreed refund/chargeback
policy. Never mix mock or sandbox revenue with real operational revenue.

## Guard-assisted payment

The current guard method creates awaiting_guard and an invoice-reference QR in
the app. It does not confirm payment or authorize exit. Anuk's authenticated admin
flow will generate the booth code and confirm the invoice later. Agree the code's
issuer, amount binding, expiration and guard identity/audit fields before adding
that endpoint. This increment deliberately does not alter his dashboard.

## Booking and barrier hand-off

The screen calls the existing completion callback only on Finish demo exit for a
paid invoice matching its booking ID with an unexpired pass. The current ParkingStateManager.completePayment targets the
current active booking; team integration should provide explicit booking-ID
settlement before supporting multiple simultaneous visits robustly. It currently
records completedAt/finalFee and releases a slot; no physical barrier opens here.

Billing now issues signed, five-minute paid exit passes and exposes authenticated,
atomic single-use consumption. Varunprasath's backend still needs to integrate
that contract with hardware and agree the acknowledgment/recovery protocol.
Unpaid invoice-reference QRs and booking entry QRs cannot authorize paid exit.

## Decisions still open

- Platform diagrams show MongoDB + Node.js/Firebase, while this component uses
  FastAPI and proposes PostgreSQL. Keep the current repository interface and
  local SQLite adapter until the team decides the production store.
- Supervisor approval is needed for rates, grace, blocks, peak windows, demand
  curve, daily cap, overtime, arrival-fee treatment and exit-hour surge policy.
- Booking charges must move to a server-authoritative source. Production must
  remove driver-controlled demand overrides and add authentication/ownership.

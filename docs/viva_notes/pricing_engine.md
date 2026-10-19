# Provisional pricing engine

## What it does
`backend/app/services/pricing_engine.py` calculates a quote without I/O or framework imports. Rules live in one dictionary. It converts aware timestamps into Colombo time, splits the stay at local midnight, rounds each day's duration to 15-minute blocks, and calculates peak, overtime and upgrade premiums on actual overlaps. Demand adds a capped linear multiplier; the daily cap applies last.

## Why this approach / alternatives
Pure functions make boundary cases easy to test. Decimal avoids binary monetary error; ROUND_HALF_UP produces whole LKR. Actual time intersections avoid applying a peak multiplier to an entire stay. A trained fee model would be harder to explain and is unnecessary: only demand forecasting needs a model.

## Limitations and assumptions
All tariffs require supervisor approval. Grace is a stay threshold, not a deduction. Overtime is a trailing portion within entry/exit; overlapping peak and overtime premiums add. Rounding happens per calendar day; padding is normal-rate. `surge_amount` includes cap discounts and rounding reconciliation and may be negative. The HTTP route uses zero upgrade delta because no authoritative slot tariff/history exists. This engine currently differs from the provisional Dart mock's extra-time interpretation; Step 7 must align it. A recorded arrival-deadline fee is a separate whole-LKR input, added once without surge inside the entry-day cap; parking grace does not erase it. The demo client supplies that existing booking amount until server-side booking storage is integrated. No database, forecasting or payment logic belongs here.

## Three viva questions
- **Why split at midnight?** The cap applies per Colombo calendar day, not per rolling 24 hours.
- **Why can surge amount be negative?** It also records the daily-cap discount and rounding adjustment so totals reconcile.
- **How is partial peak time billed?** Intersect each actual day's stay with weekday peak intervals and apply the extra 0.25 only to those minutes.

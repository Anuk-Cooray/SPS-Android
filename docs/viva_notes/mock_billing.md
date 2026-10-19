# Offline billing and integer pricing

## Approach / alternatives
MockBillingService stores demo invoices in memory and simulates confirmed digital payment without a timed delay. Guard remains awaiting_guard. Its synthetic hourly demand pattern supplies the chart and quote demand. Mock pricing mirrors the provisional backend tariff: per-day blocks, actual peak overlap, trailing overtime, exit-hour surge, half-up rounding and daily caps. Upgrades remain zero because no upgrade-rate history exists.

## Integer arithmetic
mock_pricing.dart represents fractional LKR as integer numerators over a common denominator of 240 × microseconds per minute. That denominator covers hourly rates, the 0.25 peak premium and the 0.5 overtime premium. Demand is integer permille; its linear surge is another integer fraction. Round once per day and add a reconciliation line so line items sum to the total. No double stores or calculates money. Shared backend/Dart fixtures check both engines against the same cases.

## Limitations
This is an explainable synthetic rule-based mock, not the trained Python forecast. Its forecast is labelled accordingly. Rates/rules are duplicated, so fixtures and team sign-off are essential. The arrival-deadline fee is added once without surge, inside the entry-day cap; grace waives parking only. Digital settlement is an explicit offline simulation. Backend mock sessions instead remain pending until their development callback. Restart loses memory. No provider money is charged by the mock.

## Three viva questions
- **Why integer fractions?** They preserve fractional tariff calculations without binary floating-point money errors.
- **Why test against Python fixtures?** The two languages must implement the same tariff semantics even though their numeric representations differ.
- **Why does guard remain pending?** Choosing a booth method provides no payment evidence.

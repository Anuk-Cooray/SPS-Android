# Pay-and-exit UI, breakdown and chart

## Approach / alternatives
PayAndExitScreen reuses AppColors, AppText/Manrope tabular figures, spacing/radii and PrimaryButton. A scrollable body keeps the monochrome design usable with longer invoices and three methods. The amount, Colombo time range, duration, booked arrival charge and upgrade IDs come from the quote/booking. The Visa row is explicitly sandbox-labelled. The fake 700 ms success timer is removed. A fixed bottom action starts payment or refreshes its status.

InvoiceBreakdownCard shows every ordered quote line and its total with wrapping labels. DemandForecastChart uses a small CustomPainter for a monochrome line and shaded band, with fixed 0–100% occupancy axes and Colombo labels. It handles empty and single-point series. Semantic text describes the synthetic forecast and its uncalibrated band. A chart library would add unnecessary weight to this static milestone view.

## Guard and confirmation
Booth payment remains awaiting_guard and shows an invoice-reference QR, explicitly not an exit QR. It carries an invoice ID, not a paid barrier authorization. The authenticated guard-generated workflow still belongs to later admin integration. A checkout return/session alone never calls onPaymentCompleted. The screen checks its paid invoice and prevents duplicate callbacks. Footer text does not promise real barrier hardware operation.

## Limitations
No real saved card, hosted checkout/Stripe client or hardware barrier integration. Paid-only backend exit passes are shown as QR codes; offline passes are labelled unable to open a gate. The default mock simulates payment; Backend mock sessions have an explicit Confirm mock action; configured provider sessions still require verified callbacks. Synthetic uncertainty is illustrative. Screen tests cover arrival/upgrade rows, guard waiting, pending-to-paid refresh and dark chart layout; narrow-view tests caught and shortened the button labels to fit.

## Three viva questions
- **Why scroll the body?** Real quote lines and the chart may exceed the reference design's fixed height.
- **Why label the booth QR?** Invoice identification is not single-use exit authorization.
- **When does navigation complete?** Exactly once on Finish demo exit, after paid status and an unexpired pass are checked.

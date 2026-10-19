# Step 1: repository review

Reviewed on 2026-10-19. Branch: `Rathnayake/billing-milestone-1`.
No application code changed in this step.

- The working tree was clean on `main` at `5d1595a`. No AGENTS.md files were found in the repository search.
- `pubspec.yaml` requires Dart ^3.13.5 and already includes Provider, intl, qr_flutter and google_fonts. Flutter and Dart were not found on PATH; Python 3.13.7 is available. No analyzer, tests or app launch have been run yet.
- Models use filenames such as `booking_model.dart`. Booking contains integer fees and nullable check-in/completion timestamps. It has no extension duration or upgrade timestamp/rate delta.
- `BillingService` has the two legacy methods described in the prompt; there is no billing implementation. Other service contracts must remain unchanged.
- `main.dart` currently uses one ChangeNotifierProvider, so independent billing state requires a small MultiProvider conversion and imports, rather than literally one added line.
- `completePayment` finalizes the booking and releases its slot. It must only be called after a confirmed paid invoice, never merely after a payment session is created or a guard method is selected.
- PayAndExitScreen hardcodes the time range, duration, extension fallback, upgrade amount, card and delayed success. Preserve its layout while replacing these values.
- Inspected `Resources/UI/09-M11-Pay-and-exit.png` and `13-A2-Admin-dashboard.png`. Billing uses monochrome amounts, an itemized rounded card and a bottom payment button. Admin remains owned by Anuk.
- Reuse AppColors, AppSpace, AppRadius, AppText and PrimaryButton; AppText already supplies tabular figures.
- Synthetic-data seeds: lot-main (100 LKR/hour, capacity 24), lot-new-p2 (80, 30), lot-sports (50, 18).

## Integration issues to document during implementation

The existing extensionFee is an arrival-deadline charge, not recorded parking overtime. Do not silently convert it into extension minutes or charge it twice. The new quote API needs a documented way to preserve this distinction without changing the teammate-owned Booking model.

The scope explicitly requests new `lib/data/models/billing/` models and root `.gitignore` entries despite omitting these paths from the general ownership allowlist. Treat these specific deliverables as authorized exceptions; leave unrelated paths alone. Imports needed for typed BillingService additions are part of that contract change.

Pricing parameters require supervisor/team sign-off. The platform database/backend decision (MongoDB + Node.js/Firebase versus PostgreSQL + FastAPI) remains open; use FastAPI and an in-memory repository interface for this milestone.

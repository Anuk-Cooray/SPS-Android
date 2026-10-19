# Synthetic occupancy generator

## What it does / why
The seeded generator produces 90 days of hourly rows for the three lot IDs and capacities read from Flutter mock_data.dart. Smooth morning/lunch peaks, weekend reductions, a simulated two-week semester break, rain, weekly events and random noise form an explainable signal. Occupancy rounds to integer occupied slots within capacity. The header is the data dictionary. CSVs are generated locally rather than committed as if they were observed research data.

## Alternatives / limitations
Real CCTV occupancy is unavailable for this milestone. Synthetic rows exercise the pipeline but cannot demonstrate real-world predictive accuracy. Dates and break patterns are invented; arrivals do not enforce conservation across occupied vehicles and exits. The seed makes the demo reproducible, but intentionally simple patterns favor standard models. The Dart registry reader depends on the current mock-data declaration format and raises if it cannot find lots.

## Three viva questions
- **Why synthetic?** To validate interfaces before Samudi's occupancy feed is available, without claiming real evidence.
- **Why a seed?** To regenerate the same rows and compare changes fairly.
- **Why read Dart mocks?** It keeps lot IDs/capacities consistent with the current app, while a shared registry remains future work.

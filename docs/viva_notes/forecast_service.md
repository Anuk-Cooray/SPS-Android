# Forecast API and pricing integration

## What it does / why
ForecastService lazily caches a locally trained bundle per API process. Dependency injection shares it between demand and quote routes. A lock serializes predictions and development retraining. Predictions start at the next current Colombo hourly boundary and serialize UTC timestamps with bounded occupancy fractions. The forecast schema validates finite values and an ordered band. Omitted quote demand uses the Colombo hour containing exit_time, converted with Decimal(str(level)) before pricing. The explanation discloses the synthetic source/hour.

## Alternatives / limitations
One exit-hour demand multiplier for the entire quote is a provisional tariff assumption; integrating hourly demand across a stay is later work. The current model extrapolates September synthetic patterns, not live campus observations. Missing/corrupt models return 503, rather than concealing failure with zero demand. The explicit demand override is a demo facility requiring server control in production. The band remains illustrative in-sample residual error, not calibrated confidence.

Retraining requires process environment DEBUG=true. It fits in a staging directory, validates predictions, replaces artifacts and switches the cache. Fit failure preserves the old model. Retraining is synchronous and process-local; no distributed invalidation, job queue or auth. Restart additional workers after retraining. A database/Redis cache would be premature for this checkpoint. Optional Prophet remains untested here; the executed path uses the sklearn fallback.

## Three viva questions
- **Why cache the bundle?** Deserializing fitted models on every quote wastes time; one process-local object suffices for this demo.
- **Why return 503 when it is missing?** Model availability is a service problem; inventing zero demand would silently alter fees.
- **What makes the pricing integration dynamic?** When the caller omits demand, predicted occupancy for the selected hour sets the rule-based surge multiplier; the forecasting library itself is not the novelty.

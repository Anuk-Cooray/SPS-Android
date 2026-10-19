# Hourly occupancy preprocessing

## What it does / why
The loader validates aware timestamps, capacities and occupancy bounds; converts instants to UTC; keeps the last exact duplicate per lot; sorts and resamples hourly without mixing lots. Last occupancy/capacity, summed arrivals, mean rain and maximum event flag summarize within-hour rows. Missing hours carry past state forward and are marked `was_imputed`. Features express Colombo hour, day, weekend, peak, rain and events. Occupancy rate is occupied slots divided by capacity. Prophet-ready data contains ds/y/rain.

## Alternatives / limitations
Forward fill is transparent and avoids using future observations to fill training history. It can still be wrong across long camera outages; production should reject or model such gaps. Training refuses imputed targets for this demo's metrics. Last duplicate wins assumes input order means latest revision. Prophet requires naive wall-time ds, so only its adapter removes timezone information after conversion to Colombo. No random split or backward interpolation is used.

## Three viva questions
- **Why resample per lot?** Different capacities and histories must not be merged.
- **Why mark filled rows?** Imputed occupancy is an assumption, not observed ground truth.
- **Why convert to local time for features?** Campus demand follows local class times, while UTC preserves storage consistency.

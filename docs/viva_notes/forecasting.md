# Baseline forecasting and prediction

## Structure / model choice
Auto mode uses optional Prophet: additive trend plus daily/weekly seasonal patterns and rain regressor. If Prophet cannot be imported, a seeded GradientBoostingRegressor learns a sum of 100 shallow depth-3 regression trees, each correcting earlier residuals. Its inputs are local hour/day/weekend/peak, rain and event flags. Both are standard library models trained here; there are no external pretrained weights. No deep learning is needed. Boosting avoids Prophet's optional installation burden; a same-hour-last-week baseline tests whether either model adds value. Novelty is demand-aware pricing feeding billing, not merely using a forecasting library.

## Data / validation
Data is SYNTHETIC: 90 hourly days per mock lot, not campus measurements. Each lot holds out its last seven days chronologically. Forecast rain/events default to zero in both evaluation and inference. Same-hour-last-week uses training observations only. Report MAE/RMSE in occupancy fractions and MAPE percent excluding zero targets with counts. Only after recording holdout metrics is the saved demo model refit on all history. CLI prediction reloads the model and clamps occupancy/demand to [0,1]. The Step 5 API caches that bundle and predicts current-time hours; an omitted quote demand uses the exit-hour prediction. See metrics.json for actual outcomes; do not claim real predictive validity.

## Limitations / alternatives
The plotted residual band uses in-sample 90th-percentile absolute errors, not calibrated future uncertainty. Synthetic patterns and fixed weather assumptions limit external validity. Semester breaks and future events are not known features; unseen calendar changes can defeat the baseline. MAPE exaggerates errors near zero. Prophet execution depends on an optional installation and is not validated by the current fallback run. XGBoost/LSTM comparisons, real CCTV occupancy and calibrated intervals belong to later work.

## Three viva questions
- **Why chronological testing?** Random splitting lets future patterns leak into historical evaluation.
- **Why refit after testing?** The demo uses all available history while the recorded metrics remain independent holdout results.
- **Is the band a 90% guarantee?** No; it is an illustrative training-residual range needing future calibration.

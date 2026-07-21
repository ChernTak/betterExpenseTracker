-- Tier B inference moved on-device (TFLite, run inside the Flutter app) —
-- see front-end/lib/services/tier_b_inference_service.dart. The Postgres
-- cache this table backed (populated by the now-deleted ai/predict_tier_b.py,
-- read by forecast.service.js) is no longer needed.
DROP TABLE forecast_cache;

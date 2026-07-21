-- Logs each on-device Tier B prediction (see
-- front-end/lib/services/tier_b_inference_service.dart) so accuracy can be
-- checked later against what the user actually spent that month — see
-- ai/evaluate_tier_b.py. Purely a monitoring record; nothing in this app
-- reads it back to serve a forecast (that's forecaster.js's job, live).
CREATE TABLE forecast_predictions_log (
  prediction_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  month           SMALLINT CHECK (month BETWEEN 1 AND 12) NOT NULL,
  year            SMALLINT CHECK (year >= 2000) NOT NULL,
  predicted_p10   NUMERIC(12, 2) NOT NULL,
  predicted_p50   NUMERIC(12, 2) NOT NULL,
  predicted_p90   NUMERIC(12, 2) NOT NULL,
  model_version   VARCHAR(64) NOT NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_forecast_predictions_log_user_month ON forecast_predictions_log(user_id, month, year);

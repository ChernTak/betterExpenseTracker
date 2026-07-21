-- Caches the Tier B trained-regressor prediction (see ai/predict_tier_b.py
-- and predictive_budgeting_engine_summary.md) for the current month's
-- end-of-month spend forecast. forecast.service.js prefers this row when
-- present and falls back to its own JS heuristic in forecaster.js
-- otherwise — this table is populated by an offline Python script, not by
-- the Node app itself.
CREATE TABLE forecast_cache (
  forecast_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  month                     SMALLINT CHECK (month BETWEEN 1 AND 12) NOT NULL,
  year                      SMALLINT CHECK (year >= 2000) NOT NULL,
  predicted_variable_total  NUMERIC(12, 2) NOT NULL,
  model_version             VARCHAR(50) NOT NULL,
  generated_at              TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_forecast_cache_user_month UNIQUE (user_id, month, year)
);

CREATE INDEX idx_forecast_cache_user_id ON forecast_cache(user_id);

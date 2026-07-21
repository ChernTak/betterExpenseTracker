-- Tier C (income/payday prediction, see predictive_budgeting_engine_summary.md
-- and back-end/src/ml/income_forecaster.js) needs a dated log of individual
-- income events to predict from — the existing users.monthly_income
-- (001_users.sql) is a single self-reported figure with no dates, so it
-- can't support "expected date window" prediction on its own.
CREATE TABLE income_log (
  income_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  amount         NUMERIC(12, 2) CHECK (amount >= 0) NOT NULL,
  source         VARCHAR(100),
  received_date  DATE NOT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_income_log_user_id ON income_log(user_id);

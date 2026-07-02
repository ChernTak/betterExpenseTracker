CREATE TABLE budgets (
  budget_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES users(user_id) ON DELETE CASCADE,
  category           expense_category NOT NULL,
  monthly_limit      NUMERIC(12, 2) CHECK (monthly_limit >= 0) NOT NULL,
  current_spend      NUMERIC(12, 2) CHECK (current_spend >= 0) NOT NULL DEFAULT 0,
  month              SMALLINT CHECK (month BETWEEN 1 AND 12) NOT NULL,
  year               SMALLINT CHECK (year >= 2000) NOT NULL,
  rollover_amount    NUMERIC(12, 2) NOT NULL DEFAULT 0,
  alert_threshold    NUMERIC(5, 2) NOT NULL DEFAULT 75.00,
  updated_at         TIMESTAMP DEFAULT NOW(),

  CONSTRAINT uq_budget_user_cat_month UNIQUE (user_id, category, month, year)
);

CREATE INDEX idx_budgets_user_id ON budgets(user_id);
CREATE INDEX idx_budgets_month_year ON budgets(month, year);
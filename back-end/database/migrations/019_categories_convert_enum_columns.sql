-- expense_category was a fixed enum; categories are now per-user rows (see
-- 018_categories.sql), so these columns just store the category's `key`
-- string. Existing values survive unchanged (enum labels and their text
-- form are identical for every value in this set).
--
-- v_budget_utilization and v_expenses_with_ml_predictions (013_views.sql)
-- select these columns, and Postgres refuses to ALTER COLUMN TYPE while a
-- view depends on it — drop and recreate them (definitions unchanged)
-- around the column type changes.
DROP VIEW v_budget_utilization;
DROP VIEW v_expenses_with_ml_predictions;

ALTER TABLE expenses ALTER COLUMN category TYPE VARCHAR(60) USING category::text;
ALTER TABLE budgets ALTER COLUMN category TYPE VARCHAR(60) USING category::text;
ALTER TABLE wishlist ALTER COLUMN category TYPE VARCHAR(60) USING category::text;
ALTER TABLE ml_model_output ALTER COLUMN predicted_category TYPE VARCHAR(60) USING predicted_category::text;
ALTER TABLE ml_model_output ALTER COLUMN corrected_category TYPE VARCHAR(60) USING corrected_category::text;

DROP TYPE expense_category;

CREATE VIEW v_budget_utilization AS
SELECT
  b.user_id,
  b.category,
  b.monthly_limit,
  b.current_spend,
  b.alert_threshold,
  ROUND((b.current_spend / NULLIF(b.monthly_limit, 0)) * 100, 2) AS utilization_pct,
  b.month,
  b.year
FROM budgets b
WHERE b.year = EXTRACT(YEAR FROM NOW())::SMALLINT
  AND b.month = EXTRACT(MONTH FROM NOW())::SMALLINT;

CREATE VIEW v_expenses_with_ml_predictions AS
SELECT
  e.*,
  m.predicted_category,
  m.confidence_score,
  m.user_corrected,
  m.model_version
FROM expenses e
LEFT JOIN ml_model_output m ON m.expense_id = e.expense_id;

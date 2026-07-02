-- ============================================================
-- VIEWS (convenience queries for the Node.js backend)        
-- ============================================================

-- Current month budget utilization per user
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

-- Recent expenses with ML prediction joined
CREATE VIEW v_expenses_with_ml_predictions AS
SELECT
  e.*,
  m.predicted_category,
  m.confidence_score,
  m.user_corrected,
  m.model_version
FROM expenses e
LEFT JOIN ml_model_output m ON m.expense_id = e.expense_id;


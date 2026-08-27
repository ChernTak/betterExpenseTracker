-- Phase 2 of DB cleanup. idx_budgets_month_year (month, year) is dead
-- weight: every query against budgets filters by user_id first
-- (budget.model.js), and 035_performance_indexes.sql added
-- idx_budgets_user_month_year (user_id, month, year) which already covers
-- those queries. No code depends on a bare (month, year) index, so this is
-- a pure size/write-overhead reduction with no behavior change.
--
-- Rollback: CREATE INDEX CONCURRENTLY idx_budgets_month_year ON budgets(month, year);

DROP INDEX CONCURRENTLY IF EXISTS idx_budgets_month_year;

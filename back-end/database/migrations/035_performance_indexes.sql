-- Phase 1 of DB cleanup: add indexes for hot-path queries that were
-- previously served by single-column indexes (or no index at all),
-- forcing sequential scans / in-memory sorts. Purely additive — no
-- column, type, or constraint changes, so no application code changes
-- are required. Built CONCURRENTLY so existing tables are never locked
-- for writes while the index builds.
--
-- CONCURRENTLY cannot run inside a transaction block — run each
-- statement individually (psql -f handles this correctly since it
-- doesn't wrap the whole file in one transaction by default; if you're
-- running this some other way, execute the statements one at a time).

-- expenses: the expense-list screen's query (expense.model.js#getExpensesByUserId)
-- filters user_id and sorts by transaction_date DESC, created_at DESC.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_user_txndate
  ON expenses (user_id, transaction_date DESC, created_at DESC);

-- behavioral_alerts: budget_id had NO index at all, despite being queried
-- on every expense insert via budget.service.checkAndSendAlerts (dedupe check).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_budget_type_triggered
  ON behavioral_alerts (budget_id, alert_type, triggered_at DESC);

-- behavioral_alerts: dashboard "recent alerts" panel (alert.mode.js#findRecentForUser).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_user_triggered
  ON behavioral_alerts (user_id, triggered_at DESC);

-- budgets: dashboard load (budget.model.js#getBudgetsForUser) filters
-- user_id + month + year, without category.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_budgets_user_month_year
  ON budgets (user_id, month, year);

-- income_log: income_model.listIncomeForUser filters user_id + received_date
-- range and sorts by received_date.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_income_log_user_received
  ON income_log (user_id, received_date);

-- wishlist: wishlist.model.listWishlistForUser filters user_id + status.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_wishlist_user_status
  ON wishlist (user_id, status, added_at DESC);

-- users.is_guest: guest-account cleanup job (user.model.js) filters
-- is_guest = TRUE. Partial index since guests are a small minority of rows.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_is_guest
  ON users (user_id) WHERE is_guest = TRUE;

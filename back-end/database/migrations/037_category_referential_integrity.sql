-- Phase 3 of DB cleanup. category is a free-text VARCHAR(60) since
-- categories became a per-user table (018/019_categories*.sql) — until now
-- it was only validated in the app layer (expense.service.js,
-- budget.service.js), not enforced by Postgres. categories has
-- UNIQUE(user_id, key) (018_categories.sql), so a composite FK against
-- (user_id, key) is possible and closes that gap as a DB-level backstop.
--
-- Added NOT VALID first (instant, no table scan, only checks new/changed
-- rows going forward) then validated separately (VALIDATE CONSTRAINT scans
-- existing rows but takes a light lock that doesn't block reads/writes,
-- unlike a plain ADD CONSTRAINT which would hold a heavier lock for the
-- whole scan). Confirmed zero orphan rows in this database before writing
-- this migration (see the ad-hoc orphan-check query run during this
-- migration's review — every expenses/budgets/wishlist/ml_model_output
-- category value already matches a real categories row for that user).
--
-- wishlist.category and ml_model_output.corrected_category are nullable;
-- under Postgres's default MATCH SIMPLE, a FK with any NULL column is
-- skipped, so NULL categories remain allowed and unaffected.
--
-- No ON DELETE/UPDATE action specified (defaults to NO ACTION/RESTRICT):
-- category.key is immutable and category.model.js#deleteAndReassign
-- already reassigns every dependent row to 'other' before deleting the
-- category row itself, so these constraints should never actually block a
-- legitimate delete — if they ever do, that means deleteAndReassign missed
-- a table, which is exactly the bug class this is meant to catch.

ALTER TABLE expenses
  ADD CONSTRAINT fk_expenses_category
  FOREIGN KEY (user_id, category) REFERENCES categories (user_id, key)
  NOT VALID;

ALTER TABLE budgets
  ADD CONSTRAINT fk_budgets_category
  FOREIGN KEY (user_id, category) REFERENCES categories (user_id, key)
  NOT VALID;

ALTER TABLE wishlist
  ADD CONSTRAINT fk_wishlist_category
  FOREIGN KEY (user_id, category) REFERENCES categories (user_id, key)
  NOT VALID;

ALTER TABLE ml_model_output
  ADD CONSTRAINT fk_ml_predicted_category
  FOREIGN KEY (user_id, predicted_category) REFERENCES categories (user_id, key)
  NOT VALID;

ALTER TABLE ml_model_output
  ADD CONSTRAINT fk_ml_corrected_category
  FOREIGN KEY (user_id, corrected_category) REFERENCES categories (user_id, key)
  NOT VALID;

ALTER TABLE expenses VALIDATE CONSTRAINT fk_expenses_category;
ALTER TABLE budgets VALIDATE CONSTRAINT fk_budgets_category;
ALTER TABLE wishlist VALIDATE CONSTRAINT fk_wishlist_category;
ALTER TABLE ml_model_output VALIDATE CONSTRAINT fk_ml_predicted_category;
ALTER TABLE ml_model_output VALIDATE CONSTRAINT fk_ml_corrected_category;

-- Rollback:
-- ALTER TABLE expenses DROP CONSTRAINT fk_expenses_category;
-- ALTER TABLE budgets DROP CONSTRAINT fk_budgets_category;
-- ALTER TABLE wishlist DROP CONSTRAINT fk_wishlist_category;
-- ALTER TABLE ml_model_output DROP CONSTRAINT fk_ml_predicted_category;
-- ALTER TABLE ml_model_output DROP CONSTRAINT fk_ml_corrected_category;

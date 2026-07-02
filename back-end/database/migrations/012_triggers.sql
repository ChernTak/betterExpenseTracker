-- ============================================================
-- TRIGGERS: auto-update updated_at timestamps
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_expenses_updated_at
    BEFORE UPDATE ON expenses
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_budgets_updated_at
    BEFORE UPDATE ON budgets
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_saving_goals_updated_at
    BEFORE UPDATE ON saving_goals
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_wishlist_updated_at
    BEFORE UPDATE ON wishlist
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGER: auto-update current_spend in budgets when an
-- expense is inserted or updated                             
-- ============================================================

CREATE OR REPLACE FUNCTION sync_budget_spend()
RETURNS TRIGGER AS $$
BEGIN
  -- On INSERT or UPDATE: add amount to corresponding budget row
  IF (TG_OP = 'INSERT') THEN
    UPDATE budgets
    SET current_spend = current_spend + NEW.amount,
        updated_at = NOW()
    WHERE user_id = NEW.user_id
      AND category = NEW.category
      AND month = EXTRACT(MONTH FROM NEW.transaction_date)::SMALLINT
      AND year = EXTRACT(YEAR FROM NEW.transaction_date)::SMALLINT;
      
  ELSIF (TG_OP = 'UPDATE') THEN
    -- Reverse old, add new (handles category or amount changes)
    UPDATE budgets
    SET current_spend = current_spend - OLD.amount,
        updated_at = NOW()
    WHERE user_id = OLD.user_id
      AND category = OLD.category
      AND month = EXTRACT(MONTH FROM OLD.transaction_date)::SMALLINT
      AND year = EXTRACT(YEAR FROM OLD.transaction_date)::SMALLINT;

    UPDATE budgets
    SET current_spend = current_spend + NEW.amount,
        updated_at = NOW()
    WHERE user_id = NEW.user_id
      AND category = NEW.category
      AND month = EXTRACT(MONTH FROM NEW.transaction_date)::SMALLINT
      AND year = EXTRACT(YEAR FROM NEW.transaction_date)::SMALLINT;

  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE budgets
    SET current_spend = current_spend - OLD.amount,
        updated_at = NOW()
    WHERE user_id = OLD.user_id
      AND category = OLD.category
      AND month = EXTRACT(MONTH FROM OLD.transaction_date)::SMALLINT
      AND year = EXTRACT(YEAR FROM OLD.transaction_date)::SMALLINT;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_budget_spend
    AFTER INSERT OR UPDATE OR DELETE ON expenses
    FOR EACH ROW EXECUTE FUNCTION sync_budget_spend();

-- ============================================================
-- TRIGGER: auto-update current_saved in saving_goals        
-- ============================================================

CREATE OR REPLACE FUNCTION sync_goal_saved()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE saving_goals
    SET current_saved = current_saved + NEW.amount,
        updated_at = NOW()
    WHERE goal_id = NEW.goal_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_goal_saved
    AFTER INSERT ON saving_goal_contributions
    FOR EACH ROW EXECUTE FUNCTION sync_goal_saved();
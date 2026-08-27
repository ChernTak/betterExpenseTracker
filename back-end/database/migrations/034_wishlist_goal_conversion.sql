-- A wishlist item can now resolve by becoming a funded goal instead of only
-- "bought" or "dismissed" — for planned big-ticket items (e.g. a gaming
-- chair) the user decides to save toward rather than an impulse being
-- suppressed. goal_id keeps the two rows linked so the wishlist item's
-- history survives the conversion.
ALTER TYPE wishlist_status ADD VALUE 'converted_to_goal';

ALTER TABLE wishlist ADD COLUMN goal_id UUID REFERENCES saving_goals(goal_id) ON DELETE SET NULL;

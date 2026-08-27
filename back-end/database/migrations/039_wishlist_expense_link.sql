-- A wishlist item resolved as 'purchased' now creates a real expense record
-- instead of just flipping a status flag, so the purchase actually shows up
-- in the user's spending/budget totals. expense_id keeps the two rows linked
-- the same way goal_id already links a converted-to-goal item.
ALTER TABLE wishlist ADD COLUMN expense_id UUID REFERENCES expenses(expense_id) ON DELETE SET NULL;

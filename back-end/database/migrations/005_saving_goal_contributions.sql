CREATE TABLE saving_goal_contributions (
  contribution_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id             UUID NOT NULL REFERENCES saving_goals(goal_id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  amount              NUMERIC(12, 2) CHECK (amount > 0) NOT NULL,
  note                TEXT,
  contributed_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sgc_goal_id ON saving_goal_contributions(goal_id);
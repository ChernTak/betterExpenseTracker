CREATE TABLE behavioral_alerts (
  alert_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  expense_id          UUID REFERENCES expenses(expense_id) ON DELETE SET NULL,
  budget_id           UUID REFERENCES budgets(budget_id) ON DELETE SET NULL,
  alert_type          alert_type NOT NULL,
  message             TEXT NOT NULL,
  was_acted_upon      BOOLEAN NOT NULL DEFAULT FALSE,
  action_taken        VARCHAR(100),
  delivery_channel    VARCHAR(50) NOT NULL DEFAULT 'push notification',
  triggered_at        TIMESTAMP NOT NULL DEFAULT NOW(),
  acknowledged_at     TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_alerts_user_id    ON behavioral_alerts(user_id);
CREATE INDEX idx_alerts_expense_id ON behavioral_alerts(expense_id);
CREATE INDEX idx_alerts_triggered  ON behavioral_alerts(triggered_at DESC);
CREATE TABLE wishlist (
  wishlist_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  alert_id            UUID REFERENCES behavioral_alerts(alert_id) ON DELETE SET NULL,
  item_name           VARCHAR(255) NOT NULL,
  estimated_cost      NUMERIC(12, 2) CHECK (estimated_cost > 0),
  merchant_name       VARCHAR(255),
  category            expense_category,
  delay_until_date    DATE,
  delay_days          SMALLINT CHECK (delay_days >= 0),
  status              wishlist_status NOT NULL DEFAULT 'pending',
  purchased_on        DATE,
  notes               TEXT,
  added_at            TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wishlist_user_id ON wishlist(user_id);
CREATE INDEX idx_wishlist_status ON wishlist(status);
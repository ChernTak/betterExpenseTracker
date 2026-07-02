CREATE TABLE expenses (
  expense_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES users(user_id) ON DELETE CASCADE,
  amount             NUMERIC(12, 2) CHECK (amount >= 0) NOT NULL,
  currency           VARCHAR(3) NOT NULL DEFAULT 'MYR',
  category           expense_category NOT NULL,
  merchant_name      VARCHAR(255),
  description        TEXT,
  input_method       input_method NOT NULL DEFAULT 'manual',
  ocr_raw_text       TEXT,
  voice_transcript   TEXT,
  gps_latitude       DOUBLE PRECISION CHECK (gps_latitude BETWEEN -90 AND 90),
  gps_longitude      DOUBLE PRECISION CHECK (gps_longitude BETWEEN -180 AND 180),
  location_name      VARCHAR(255),
  context_label      VARCHAR(100),
  context_metadata   JSONB,
  payment_method     VARCHAR(50),
  is_recurring       BOOLEAN NOT NULL DEFAULT FALSE,
  transaction_date   DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at         TIMESTAMP DEFAULT NOW(),
  updated_at         TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_expenses_user_id ON expenses(user_id);
CREATE INDEX idx_expenses_transaction_date ON expenses(transaction_date DESC);
CREATE INDEX idx_expenses_category ON expenses(category);
CREATE INDEX idx_expenses_context_meta ON expenses USING GIN (context_metadata);
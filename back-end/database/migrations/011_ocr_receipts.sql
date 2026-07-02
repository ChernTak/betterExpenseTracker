CREATE TABLE ocr_receipts (
  receipt_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id          UUID REFERENCES expenses(expense_id) ON DELETE SET NULL,
  user_id             UUID REFERENCES users(user_id) ON DELETE CASCADE,
  image_url           TEXT NOT NULL,
  raw_text            TEXT,
  extracted_amount    NUMERIC(12, 2),
  extracted_merchant  VARCHAR(255),
  extracted_date      DATE,
  confidence          NUMERIC(5, 4),
  processed_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ocr_user_id ON ocr_receipts(user_id);
CREATE INDEX idx_ocr_expense_id ON ocr_receipts(expense_id);
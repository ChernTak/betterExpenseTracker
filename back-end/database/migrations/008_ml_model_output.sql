CREATE TABLE ml_model_output (
  output_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id          UUID REFERENCES expenses(expense_id) ON DELETE CASCADE,
  user_id             UUID REFERENCES users(user_id) ON DELETE CASCADE,
  predicted_category  expense_category NOT NULL,
  confidence_score    NUMERIC(5, 4) NOT NULL CHECK (confidence_score BETWEEN 0 AND 1),
  user_corrected      BOOLEAN NOT NULL DEFAULT FALSE,
  corrected_category  expense_category,
  model_version       VARCHAR(50) NOT NULL,
  inference_ms        INTEGER,
  created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mlexpense_id ON ml_model_output(expense_id);
CREATE INDEX idx_ml_user_id ON ml_model_output(user_id);
CREATE INDEX idx_model_version ON ml_model_output(model_version);
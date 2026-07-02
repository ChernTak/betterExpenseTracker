CREATE TABLE recommendation_log (
  rec_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  rec_type           VARCHAR(50) NOT NULL,
  rec_title          VARCHAR(255) NOT NULL,
  rec_body           TEXT NOT NULL,
  context_snapshot   JSONB,
  was_viewed         BOOLEAN NOT NULL DEFAULT FALSE,
  was_acted_upon     BOOLEAN NOT NULL DEFAULT FALSE,
  generated_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  viewed_at          TIMESTAMP,
  acted_at           TIMESTAMP
);

CREATE INDEX idx_rec_log_user_id ON recommendation_log(user_id);
CREATE INDEX idx_rec_log_date ON recommendation_log(generated_at DESC);
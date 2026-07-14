-- Per-user, fully editable expense categories (add/remove/reorder). Replaces
-- the fixed expense_category ENUM (which can't have values removed, renamed
-- or reordered) as the source of truth for what categories exist; the enum
-- columns themselves are converted to VARCHAR in the next migration.
CREATE TABLE categories (
  category_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  key           VARCHAR(60) NOT NULL,   -- stable slug stored in expenses/budgets.category; immutable after creation
  label         VARCHAR(100) NOT NULL,
  icon          VARCHAR(50) NOT NULL,   -- key into the frontend's curated icon preset map
  color         VARCHAR(7) NOT NULL,    -- '#RRGGBB'
  keywords      TEXT,                   -- optional comma-separated merchant keywords for auto-categorization
  sort_order    INTEGER NOT NULL,
  is_protected  BOOLEAN NOT NULL DEFAULT FALSE,  -- true only for the seeded "other" row; blocks deletion
  created_at    TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_categories_user_key UNIQUE (user_id, key)
);

CREATE INDEX idx_categories_user_id ON categories(user_id);

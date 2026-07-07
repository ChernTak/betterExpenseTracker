-- Guest login creates a real user row (so all existing FK-based features
-- work unchanged) with a generated email/password nobody will ever use to
-- log in again. This flag just lets guest accounts be identified/cleaned up
-- later without guessing based on the generated email pattern.
ALTER TABLE users ADD COLUMN is_guest BOOLEAN NOT NULL DEFAULT FALSE;

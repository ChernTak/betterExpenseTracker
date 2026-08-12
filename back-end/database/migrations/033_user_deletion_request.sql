-- PDPA erasure with a recoverability window — the admin-initiated delete
-- flow now soft-deletes (deactivates + timestamps the request) first, and
-- only permanently purges the row once ADMIN_DELETION_GRACE_DAYS has
-- elapsed since deletion_requested_at (or an admin explicitly forces it).
ALTER TABLE users ADD COLUMN deletion_requested_at TIMESTAMP;

-- Separate, explicit opt-in from the existing location_consent column
-- (which only ever covers the foreground, on-demand GPS fetch behind the
-- Food tab's recommendations). Background/always-on monitoring for the
-- geofencing nudge is materially more invasive and gets its own consent
-- gate, logged under consent_type='background_location' in consent_log
-- (032_consent_log.sql already supports arbitrary consent_type values).
ALTER TABLE users ADD COLUMN background_location_consent BOOLEAN NOT NULL DEFAULT FALSE;

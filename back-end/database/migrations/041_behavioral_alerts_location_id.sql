-- 'location_nudge' alerts need to record which high_risk_locations row
-- triggered them, both so the dedupe check (once per user per location per
-- day, mirrors findRecentAlert's per-budget dedupe) can scope correctly and
-- so past location nudges stay auditable per the same intent as budget_id
-- on this table.
ALTER TABLE behavioral_alerts
  ADD COLUMN location_id UUID REFERENCES high_risk_locations(location_id) ON DELETE SET NULL;

CREATE INDEX idx_alerts_location_id ON behavioral_alerts(location_id);

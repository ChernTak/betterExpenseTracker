-- Cross-checks the printed grand total against subtotal + tax + rounding
-- (FR4.3 accuracy safeguard) so a misread digit or a missed tax line
-- doesn't silently slip through. Both columns are nullable: null means the
-- receipt didn't itemize enough (no subtotal/tax lines) to validate against,
-- distinct from false (itemized, but the numbers didn't reconcile).
ALTER TABLE ocr_receipts ADD COLUMN is_math_valid BOOLEAN;
ALTER TABLE ocr_receipts ADD COLUMN computed_total NUMERIC(12, 2);

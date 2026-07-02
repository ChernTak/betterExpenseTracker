-- The OCR flow (FR4.2/FR4.3) uses Google ML Kit's on-device text
-- recognition and only sends the recognized text to the backend for
-- parsing — the receipt photo itself is never uploaded/stored, so
-- image_url has no value to write here.
ALTER TABLE ocr_receipts ALTER COLUMN image_url DROP NOT NULL;

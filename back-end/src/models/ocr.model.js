const db = require('../config/db');

// FR4.3 — audit trail of what OCR extracted, regardless of whether the user
// kept the parsed values or edited them before saving.
exports.insertReceipt = ({ userId, rawText, merchant, amount, date, confidence }) => {
  const query = `
    INSERT INTO ocr_receipts (user_id, raw_text, extracted_merchant, extracted_amount, extracted_date, confidence)
    VALUES ($1, $2, $3, $4, $5, $6)
    RETURNING *
  `;
  return db.query(query, [userId, rawText, merchant, amount, date, confidence]);
};

// Called once the user confirms the scanned receipt and saves it as an
// expense, so the audit row can be traced back to what it became.
exports.linkExpense = (receiptId, expenseId, userId) => {
  const query = `
    UPDATE ocr_receipts
    SET expense_id = $1
    WHERE receipt_id = $2 AND user_id = $3
    RETURNING *
  `;
  return db.query(query, [expenseId, receiptId, userId]);
};

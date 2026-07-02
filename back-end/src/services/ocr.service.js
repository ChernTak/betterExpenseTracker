const ocrModel = require('../models/ocr.model');

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

// Prefers a line that looks like a total ("TOTAL: RM12.34"); falls back to
// the largest currency-shaped number anywhere in the receipt, since totals
// are usually the largest amount on the page.
function extractAmount(text) {
  const totalLineRegex = /(?:total|amount due|grand total|amount)\s*[:\-]?\s*(?:RM|MYR|\$)?\s*([\d,]+\.\d{2})/i;
  for (const line of text.split('\n')) {
    const match = line.match(totalLineRegex);
    if (match) return parseFloat(match[1].replace(/,/g, ''));
  }

  const allAmounts = [...text.matchAll(/(?:RM|MYR|\$)?\s*(\d[\d,]*\.\d{2})/g)]
    .map((m) => parseFloat(m[1].replace(/,/g, '')))
    .filter((n) => Number.isFinite(n));
  if (allAmounts.length === 0) return null;
  return Math.max(...allAmounts);
}

// Tries a few common receipt date formats and normalizes to ISO yyyy-mm-dd.
function extractDate(text) {
  const patterns = [
    { re: /(\d{4})-(\d{2})-(\d{2})/, toIso: (m) => `${m[1]}-${m[2]}-${m[3]}` },
    {
      re: /(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})/,
      toIso: (m) => `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`,
    },
    {
      re: /(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})/,
      toIso: (m) => {
        const monthIndex = MONTHS.indexOf(m[2].slice(0, 3).toLowerCase());
        if (monthIndex === -1) return null;
        return `${m[3]}-${String(monthIndex + 1).padStart(2, '0')}-${m[1].padStart(2, '0')}`;
      },
    },
  ];

  for (const { re, toIso } of patterns) {
    const match = text.match(re);
    if (!match) continue;
    const iso = toIso(match);
    if (iso && !Number.isNaN(new Date(iso).getTime())) return iso;
  }
  return null;
}

// Receipts conventionally print the store/merchant name as the first
// meaningful line; skip lines that are just symbols/numbers (logos, borders).
function extractMerchant(text) {
  const lines = text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
  const candidate = lines.find((line) => /[a-zA-Z]{3,}/.test(line));
  return (candidate || lines[0] || null)?.slice(0, 255) ?? null;
}

// POST /api/ocr/parse — the app already ran Google ML Kit's on-device text
// recognition; this just pulls merchant/date/amount out of that raw text
// and records an audit row (FR4.3), no image is uploaded or stored.
exports.parseReceipt = async (req, res) => {
  const { rawText } = req.body;
  if (!rawText || typeof rawText !== 'string' || !rawText.trim()) {
    return res.status(400).json({ message: 'rawText is required' });
  }

  const merchant = extractMerchant(rawText);
  const date = extractDate(rawText);
  const amount = extractAmount(rawText);

  // On-device ML Kit text recognition doesn't expose a confidence score the
  // way Cloud Vision does, so this is a coarse proxy: how many of the three
  // fields we could confidently pull out of the raw text.
  const fieldsFound = [merchant, date, amount].filter((v) => v !== null && v !== undefined).length;
  const confidence = fieldsFound / 3;

  try {
    const result = await ocrModel.insertReceipt({
      userId: req.user.userId,
      rawText,
      merchant,
      amount,
      date,
      confidence,
    });
    const receipt = result.rows[0];
    return res.status(200).json({
      receiptId: receipt.receipt_id,
      merchant,
      date,
      amount,
      confidence,
    });
  } catch (err) {
    console.error('Parse receipt error', err);
    return res.status(500).json({ message: 'Failed to save OCR result', error: err.message });
  }
};

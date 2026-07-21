const ocrModel = require('../models/ocr.model');

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

// A receipt line often has qualifier text between the label and the number
// ("TakeOut Total (incl Tax)   15.98"), so instead of anchoring the number
// right after the keyword, take the last currency-shaped number on the line.
function lastAmountOnLine(line) {
  const matches = [...line.matchAll(/(\d[\d,]*\.\d+)/g)];
  if (matches.length === 0) return null;
  return parseFloat(matches[matches.length - 1][1].replace(/,/g, ''));
}

const STRONG_TOTAL_REGEX = /\b(?:grand total|total due|amount due)\b/i;
const TOTAL_WORD_REGEX = /\btotal\b/i;
// Malaysia rounds cash payments to the nearest 5 sen, so receipts commonly
// print a separate "Rounding Adjustment" line right after the total — add
// it in so the extracted amount matches what was actually paid, not the
// pre-rounding subtotal-with-tax figure.
// The layout separator (a colon, e.g. "Rounding: -0.02") is matched on its
// own — the minus sign lives inside the numeric capture group instead of a
// shared "[:\-]?" class, so a bare "Rounding -0.05" (no colon) can't have
// its "-" mistaken for the separator and stripped from the number.
const ROUNDING_REGEX = /\bround(?:ing)?(?:\s*adj(?:ustment|ust)?)?\b\s*:?\s*(-?\s*[\d,]+\.\d+)/i;

function applyRounding(lines, totalIndex, amount) {
  for (let i = totalIndex + 1; i < Math.min(lines.length, totalIndex + 3); i++) {
    const match = lines[i].match(ROUNDING_REGEX);
    if (!match) continue;
    const cleaned = match[1].replace(/\s+/g, '').replace(/,/g, '');
    return Math.round((amount + parseFloat(cleaned)) * 100) / 100;
  }
  return amount;
}

// Prefers a line that looks like a total ("TOTAL: RM12.34"); falls back to
// the largest currency-shaped number anywhere in the receipt, since totals
// are usually the largest amount on the page.
function extractAmount(text) {
  const lines = text.split('\n');

  // \btotal\b (word boundary) naturally excludes "subtotal" — there's no
  // boundary between "sub" and "total" since both are word characters —
  // without needing to special-case it.
  for (const line of lines) {
    if (!STRONG_TOTAL_REGEX.test(line)) continue;
    const amount = lastAmountOnLine(line);
    if (amount !== null) return amount;
  }

  for (let i = 0; i < lines.length; i++) {
    if (!TOTAL_WORD_REGEX.test(lines[i])) continue;
    const amount = lastAmountOnLine(lines[i]);
    if (amount !== null) return applyRounding(lines, i, amount);
  }

  const allAmounts = [...text.matchAll(/(\d[\d,]*\.\d{2})/g)]
    .map((m) => parseFloat(m[1].replace(/,/g, '')))
    .filter((n) => Number.isFinite(n));
  if (allAmounts.length === 0) return null;
  return Math.max(...allAmounts);
}

const SUBTOTAL_WORD_REGEX = /\bsub[\s-]?total\b/i;
// Malaysian receipts label this "Tax", "SST" (Sales & Service Tax), "GST",
// or "Service Tax" depending on the era/regime — matched generically rather
// than special-cased per label name.
const TAX_WORD_REGEX = /\b(?:service\s*tax|sst|gst|vat|tax)\b/i;

// Shared by extractSubtotal/extractTaxAmount below — same "first matching
// line with a currency-shaped number on it" approach as extractAmount.
function extractLineAmount(lines, keywordRegex, { excludeTotalLines = false } = {}) {
  for (const line of lines) {
    if (!keywordRegex.test(line)) continue;
    // A total line can mention tax in passing ("Total (incl Tax) 15.98")
    // without being a distinct tax-amount line — \btotal\b doesn't match
    // "Subtotal" (no word boundary between "sub" and "total"), so this only
    // screens out true total/grand-total lines, not the subtotal line itself.
    if (excludeTotalLines && TOTAL_WORD_REGEX.test(line)) continue;
    const amount = lastAmountOnLine(line);
    if (amount !== null) return amount;
  }
  return null;
}

function extractSubtotal(lines) {
  return extractLineAmount(lines, SUBTOTAL_WORD_REGEX);
}

function extractTaxAmount(lines) {
  return extractLineAmount(lines, TAX_WORD_REGEX, { excludeTotalLines: true });
}

// Unlike applyRounding (which only looks a couple of lines below a known
// total line, so it doesn't misattribute an unrelated rounding-shaped line
// elsewhere on the receipt), this scans the whole receipt — the
// cross-validation equation below just needs to know whether a rounding
// adjustment was printed at all, not where relative to the total.
function extractRoundingAdjustment(lines) {
  for (const line of lines) {
    const match = line.match(ROUNDING_REGEX);
    if (!match) continue;
    return parseFloat(match[1].replace(/\s+/g, '').replace(/,/g, ''));
  }
  return 0;
}

// Cross-checks the printed grand total against its own components
// (subtotal + tax + rounding) — three independently-OCR'd short numbers
// agreeing is a stronger accuracy signal than trusting a single total
// figure, and it catches a misread digit or a missed tax line that would
// otherwise slip through silently. Returns nulls when there isn't a full
// subtotal+tax breakdown on the receipt to validate against (e.g. a simple
// receipt that only prints a total) rather than flagging it as invalid.
function crossValidateTotal({ subtotal, taxAmount, roundingAdjustment, grandTotalPaid }) {
  if (subtotal === null || taxAmount === null || grandTotalPaid === null) {
    return { isMathValid: null, computedTotal: null };
  }
  const computedTotal = Math.round((subtotal + taxAmount + roundingAdjustment) * 100) / 100;
  const isMathValid = Math.abs(computedTotal - grandTotalPaid) < 0.02;
  return { isMathValid, computedTotal };
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
// Malaysian receipts commonly print the registered legal entity (e.g.
// "GOLDEN ARCHES RESTAURANTS SDN BHD") above the actual trading/brand name
// (e.g. "McDonald's") — prefer the brand name and only fall back to the
// legal entity line if nothing else looks like a name.
const LEGAL_ENTITY_REGEX = /\b(sdn\.?\s*bhd\.?|berhad|enterprise|holdings|corp(?:oration)?)\b/i;
// Ticket/queue headers and registered-office boilerplate that precede the
// actual outlet name on receipt-style tickets (e.g. "Your order number is").
const BOILERPLATE_REGEX = /\b(your\s+order\s+number|order\s*(no\.?|number|#)|queue\s*(no\.?|number)?|ticket\s*(no\.?|number)?|receipt\s*no|thank\s+you|invoice)\b/i;
// Registered-office address lines that sit between the legal entity name
// and the actual outlet name.
const ADDRESS_REGEX = /\b(jalan|lorong|persiaran|lebuh|lot\s*\d|level\s*\d|floor|tingkat|taman|bangunan|wilayah|selangor|kuala lumpur|putrajaya|labuan|johor|penang|pulau pinang|perak|melaka|malacca|negeri sembilan|pahang|kedah|perlis|kelantan|terengganu|sabah|sarawak)\b/i;
// A website/email line (e.g. "www.mcdonalds.com.my") isn't a printed store
// name — it must be excluded here so the loop below falls through to
// extractDomainMerchant, which parses the brand out of it instead of
// returning the raw URL.
const URL_LINE_REGEX = /(?:https?:\/\/|www\.)|[\w.+-]+@[a-z0-9-]+\.[a-z]{2,}|\b[a-z0-9-]+\.(?:com|net|org|co|biz|my)\b/i;
const looksLikeName = (line) => /[a-zA-Z]{3,}/.test(line);
const isNoisyNameLine = (line) =>
  LEGAL_ENTITY_REGEX.test(line) ||
  BOILERPLATE_REGEX.test(line) ||
  ADDRESS_REGEX.test(line) ||
  URL_LINE_REGEX.test(line) ||
  // A total/subtotal line (reusing the same keyword regex extractAmount
  // anchors on) is never the merchant name — without a "TAX INVOICE"
  // marker to bound the header region, this stops receipts whose header
  // is all noise from returning a price row before we ever consult the
  // domain fallback.
  TOTAL_WORD_REGEX.test(line);

// Receipts print the legal entity ("Gerbang Alaf Restaurants Sdn Bhd") but
// rarely print the parent-brand name in a form the line heuristics above can
// isolate — instead of maintaining a hardcoded legal-entity -> brand lookup
// table, pull the brand out of the receipt's own website/email domain
// (e.g. "www.mcdonalds.com.my", "info@mcdonalds.com.my"), which is printed
// verbatim on most invoices/receipts regardless of which subsidiary issued it.
const EMAIL_DOMAIN_REGEX = /[\w.+-]+@([a-z0-9-]+)\.[a-z.]{2,}/i;
const WEB_DOMAIN_REGEX = /(?:https?:\/\/)?(?:www\.)?([a-z0-9-]+)\.(?:com|net|org|co|biz|my)(?:\.[a-z]{2,3})?\b/i;

function extractDomainMerchant(text) {
  const match = text.match(EMAIL_DOMAIN_REGEX) || text.match(WEB_DOMAIN_REGEX);
  if (!match) return null;

  // Strip "www."/".com"/country-code suffixes (already excluded by the
  // capture group itself) and title-case what's left, e.g.
  // "mcdonalds" -> "Mcdonalds".
  const name = match[1].replace(/[-_]/g, ' ').trim().toLowerCase();
  if (!name) return null;
  return name.charAt(0).toUpperCase() + name.slice(1);
}

function extractMerchant(text) {
  const lines = text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

  // OCR sometimes splits a single printed line (e.g. "Gerbang Alaf
  // Restaurants Sdn Bhd") across several recognized lines, so a legal
  // entity suffix a couple of lines below still marks this whole block as
  // the registered entity, not the outlet name.
  const isPartOfLegalEntityBlock = (index) =>
    LEGAL_ENTITY_REGEX.test(lines.slice(index, index + 3).join(' '));

  // Malaysian tax invoices conventionally print the outlet/brand name
  // directly above the "TAX INVOICE" marker line.
  const taxInvoiceIndex = lines.findIndex((line) => /\btax\s+invoice\b/i.test(line));
  if (taxInvoiceIndex > 0) {
    for (let i = taxInvoiceIndex - 1; i >= 0; i--) {
      const line = lines[i];
      if (!looksLikeName(line) || isNoisyNameLine(line) || isPartOfLegalEntityBlock(i)) continue;
      return line.slice(0, 255);
    }
  }

  // When there's a "TAX INVOICE" marker, the outlet name (if present at
  // all) is above it — product/total lines below are never candidates, so
  // this stays scoped to the same header region as the backward scan above
  // instead of scanning the whole receipt body.
  const headerEnd = taxInvoiceIndex > 0 ? taxInvoiceIndex : lines.length;
  for (let i = 0; i < headerEnd; i++) {
    const line = lines[i];
    if (!looksLikeName(line) || isNoisyNameLine(line) || isPartOfLegalEntityBlock(i)) continue;
    return line.slice(0, 255);
  }

  // Dynamic fallback: no line before the product rows read as a clean
  // outlet name (e.g. every candidate line was a legal entity or address) —
  // the receipt's own domain names the brand without us hardcoding a
  // legal-entity-to-brand mapping.
  const domainMerchant = extractDomainMerchant(text);
  if (domainMerchant) return domainMerchant;

  const candidate = lines.find(looksLikeName);
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

  // Arithmetic cross-check (FR4.3 accuracy safeguard): does subtotal + tax +
  // rounding reconcile with the printed grand total? isMathValid is null
  // (not false) when the receipt doesn't itemize enough to check.
  const lines = rawText.split('\n');
  const subtotal = extractSubtotal(lines);
  const taxAmount = extractTaxAmount(lines);
  const roundingAdjustment = extractRoundingAdjustment(lines);
  const { isMathValid, computedTotal } = crossValidateTotal({
    subtotal,
    taxAmount,
    roundingAdjustment,
    grandTotalPaid: amount,
  });

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
      isMathValid,
      computedTotal,
    });
    const receipt = result.rows[0];
    return res.status(200).json({
      receiptId: receipt.receipt_id,
      merchant,
      date,
      amount,
      confidence,
      // false means the printed total didn't reconcile with subtotal + tax
      // + rounding — the frontend should prompt the user to double-check
      // the values before saving; computedTotal is the reconciled figure
      // derived from those parts, offered as a corrected suggestion.
      isMathValid,
      computedTotal,
    });
  } catch (err) {
    console.error('Parse receipt error', err);
    return res.status(500).json({ message: 'Failed to save OCR result', error: err.message });
  }
};

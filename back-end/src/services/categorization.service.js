const { KEYWORD_MAP, CATEGORIES } = require('../config/categories');
const embeddingService = require('./embedding.service');
const categoryModel = require('../models/category.model');

// Matches the 0.75 gate the frontend AutoCategorizationService also applies,
// so a result cached from here still gets flagged for review consistently.
const CONFIDENCE_THRESHOLD = 0.75;

// Lowercases and strips punctuation so "Starbucks, KLCC!" and "starbucks
// klcc" hit the same keyword/embedding path.
function normalizeMerchantText(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// A row is "custom" if its key isn't one of the 13 seeded defaults — a
// renamed default (key is immutable, only label/icon/color change) still
// matches its original KEYWORD_MAP/CATEGORY_DESCRIPTIONS entry, so it isn't
// missing anything the way a genuinely new category is.
function isCustomCategory(key) {
  return !CATEGORIES.includes(key);
}

// A brand-new custom category (added via Manage Categories) has no entry in
// KEYWORD_MAP and no description embedding, so it would otherwise never be
// auto-suggested. Its own comma-separated `keywords` plug into the cheap
// substring pass here (checked first, since they're a more deliberate
// signal than the global defaults); the same text (or the label, if no
// keywords were set) also seeds the embedding fallback below.
function buildCustomKeywordMap(customCategoryRows) {
  const map = {};
  for (const row of customCategoryRows) {
    if (!row.keywords) continue;
    for (const keyword of row.keywords.split(',')) {
      const trimmed = keyword.trim().toLowerCase();
      if (trimmed) map[trimmed] = row.key;
    }
  }
  return map;
}

// First pass: cheap substring match against custom keywords, then
// KEYWORD_MAP. Deterministic and free, so it's tried before ever touching
// the embedding model.
function matchKeyword(normalizedText, customKeywordMap) {
  for (const [keyword, category] of Object.entries(customKeywordMap)) {
    if (normalizedText.includes(keyword)) return category;
  }
  for (const [keyword, category] of Object.entries(KEYWORD_MAP)) {
    if (normalizedText.includes(keyword)) return category;
  }
  return null;
}

// Core resolution logic, kept separate from the Express handler below so it
// can be unit-tested or reused without an HTTP round trip. userId is
// optional so existing callers that don't have one still work (falling back
// to the global keyword map only, with no custom categories to consider).
async function classifyMerchant(rawText, userId) {
  const normalized = normalizeMerchantText(rawText);

  const customRows = userId ? (await categoryModel.listForUser(userId)).rows.filter((row) => isCustomCategory(row.key)) : [];

  const customKeywordMap = buildCustomKeywordMap(customRows);
  const keywordCategory = matchKeyword(normalized, customKeywordMap);
  if (keywordCategory) {
    console.log(`[categorize] source=keyword text="${rawText}" -> ${keywordCategory}`);
    return { category: keywordCategory, confidence: 1, needsReview: false, source: 'keyword' };
  }

  // Same signal as the keyword map above (custom keywords, falling back to
  // the label), just embedded instead of substring-matched — this is what
  // lets a custom category win the embedding fallback at all.
  const customCategories = customRows.map((row) => ({
    id: row.category_id,
    key: row.key,
    text: row.keywords && row.keywords.trim() ? row.keywords : row.label,
  }));

  const { category, confidence } = await embeddingService.classifyByEmbedding(normalized, customCategories);
  const needsReview = confidence < CONFIDENCE_THRESHOLD;
  console.log(`[categorize] source=embedding text="${rawText}" -> ${category} (${confidence.toFixed(3)})`);
  return { category, confidence, needsReview, source: 'embedding' };
}

// POST /api/expenses/categorize
async function categorize(req, res) {
  const { text } = req.body;
  if (!text || typeof text !== 'string' || !text.trim()) {
    return res.status(400).json({ message: 'text is required' });
  }

  try {
    const result = await classifyMerchant(text, req.user.userId);
    return res.status(200).json(result);
  } catch (err) {
    console.error('Categorize error', err);
    return res.status(500).json({ message: 'Failed to categorize expense', error: err.message });
  }
}

module.exports = { classifyMerchant, categorize, normalizeMerchantText };

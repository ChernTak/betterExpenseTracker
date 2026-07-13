const { KEYWORD_MAP } = require('../config/categories');
const embeddingService = require('./embedding.service');

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

// First pass: cheap substring match against KEYWORD_MAP. Deterministic and
// free, so it's tried before ever touching the embedding model.
function matchKeyword(normalizedText) {
  for (const [keyword, category] of Object.entries(KEYWORD_MAP)) {
    if (normalizedText.includes(keyword)) return category;
  }
  return null;
}

// Core resolution logic, kept separate from the Express handler below so it
// can be unit-tested or reused without an HTTP round trip.
async function classifyMerchant(rawText) {
  const normalized = normalizeMerchantText(rawText);

  const keywordCategory = matchKeyword(normalized);
  if (keywordCategory) {
    console.log(`[categorize] source=keyword text="${rawText}" -> ${keywordCategory}`);
    return { category: keywordCategory, confidence: 1, needsReview: false, source: 'keyword' };
  }

  const { category, confidence } = await embeddingService.classifyByEmbedding(normalized);
  const needsReview = confidence < CONFIDENCE_THRESHOLD;
  console.log(`[categorize] source=embedding text="${rawText}" -> ${category} (${confidence.toFixed(3)})`);
  return { category, confidence, needsReview, source: 'embedding' };
}

// POST /api/expenses/categorize — stateless classification, so it's not
// scoped to req.user beyond the JWT check the router already applies.
async function categorize(req, res) {
  const { text } = req.body;
  if (!text || typeof text !== 'string' || !text.trim()) {
    return res.status(400).json({ message: 'text is required' });
  }

  try {
    const result = await classifyMerchant(text);
    return res.status(200).json(result);
  } catch (err) {
    console.error('Categorize error', err);
    return res.status(500).json({ message: 'Failed to categorize expense', error: err.message });
  }
}

module.exports = { classifyMerchant, categorize };

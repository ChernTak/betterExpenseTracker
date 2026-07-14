const { CATEGORY_DESCRIPTIONS } = require('../config/categories');

// @xenova/transformers is ESM-only, so it's loaded via a cached dynamic
// import() rather than require() — this file otherwise stays CommonJS like
// the rest of the backend (package.json has no "type": "module").
let extractorPromise = null;
function getExtractor() {
  if (!extractorPromise) {
    extractorPromise = (async () => {
      const { pipeline } = await import('@xenova/transformers');
      return pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
    })();
  }
  return extractorPromise;
}

// Mean-pooled, L2-normalized sentence embedding, so cosine similarity
// reduces to a plain dot product in cosineSimilarity() below.
async function embed(text) {
  const extractor = await getExtractor();
  const output = await extractor(text, { pooling: 'mean', normalize: true });
  return Array.from(output.data);
}

function cosineSimilarity(a, b) {
  let dot = 0;
  for (let i = 0; i < a.length; i += 1) dot += a[i] * b[i];
  return dot;
}

// Category description embeddings are computed once (first call) and kept
// in memory for the lifetime of the process — recomputing them per request
// would be by far the slowest part of every categorize call.
let categoryEmbeddingsPromise = null;
function getCategoryEmbeddings() {
  if (!categoryEmbeddingsPromise) {
    categoryEmbeddingsPromise = (async () => {
      const entries = Object.entries(CATEGORY_DESCRIPTIONS);
      const embeddings = {};
      for (const [category, description] of entries) {
        embeddings[category] = await embed(description);
      }
      return embeddings;
    })();
  }
  return categoryEmbeddingsPromise;
}

// A custom category (added via Manage Categories) has no entry in
// CATEGORY_DESCRIPTIONS, so without this it could never be the winner of
// the embedding comparison below no matter how well its keywords/label
// matched the merchant text. Keyed by category_id (globally unique, unlike
// `key` which is only unique per-user) rather than the fixed defaults'
// startup-computed map, since these are created/edited/deleted at runtime.
// Cache invalidation is just "recompute if the text changed" — cheap
// (single sentence embed) and avoids needing an explicit eviction path;
// unbounded growth over a server's lifetime is fine at this app's scale.
const customCategoryEmbeddingCache = new Map();
async function getCustomCategoryEmbedding(categoryId, text) {
  const cached = customCategoryEmbeddingCache.get(categoryId);
  if (cached && cached.text === text) return cached.embedding;

  const embedding = await embed(text);
  customCategoryEmbeddingCache.set(categoryId, { text, embedding });
  return embedding;
}

// Embeds the (already keyword-normalized) merchant text and returns the
// category description/custom-category text it's closest to, with the
// similarity score used directly as the confidence. customCategories is
// `{ id, key, text }[]` — the caller's own (non-default) categories, text
// being their keywords if set or their label otherwise (see
// categorization.service.js).
async function classifyByEmbedding(normalizedText, customCategories = []) {
  const [textEmbedding, categoryEmbeddings, customEmbeddings] = await Promise.all([
    embed(normalizedText),
    getCategoryEmbeddings(),
    Promise.all(
      customCategories.map(async ({ id, key, text }) => ({
        key,
        embedding: await getCustomCategoryEmbedding(id, text),
      })),
    ),
  ]);

  let bestCategory = 'other';
  let bestScore = -Infinity;
  for (const [category, embedding] of Object.entries(categoryEmbeddings)) {
    const score = cosineSimilarity(textEmbedding, embedding);
    if (score > bestScore) {
      bestScore = score;
      bestCategory = category;
    }
  }
  for (const { key, embedding } of customEmbeddings) {
    const score = cosineSimilarity(textEmbedding, embedding);
    if (score > bestScore) {
      bestScore = score;
      bestCategory = key;
    }
  }
  return { category: bestCategory, confidence: bestScore };
}

// Called once at server startup (see app.js) so the model is already
// downloaded/loaded and category embeddings are precomputed before the
// first real request arrives, instead of stalling that first request.
async function preload() {
  await getCategoryEmbeddings();
}

module.exports = { classifyByEmbedding, preload };

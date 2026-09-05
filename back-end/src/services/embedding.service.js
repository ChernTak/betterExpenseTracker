const { CATEGORY_DESCRIPTIONS } = require('../config/categories');

// @xenova/transformers is ESM-only, so it's loaded via cached dynamic import() while this file stays CommonJS.
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

// Category embeddings are computed once and cached in memory; recomputing per request would dominate every categorize call.
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

// Custom categories have no CATEGORY_DESCRIPTIONS entry, so this caches their embeddings by category_id, recomputing only when the text changes.
const customCategoryEmbeddingCache = new Map();
async function getCustomCategoryEmbedding(categoryId, text) {
  const cached = customCategoryEmbeddingCache.get(categoryId);
  if (cached && cached.text === text) return cached.embedding;

  const embedding = await embed(text);
  customCategoryEmbeddingCache.set(categoryId, { text, embedding });
  return embedding;
}

// Returns the closest category description/custom text to the normalized merchant text, using similarity score directly as confidence.
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

// Called once at startup (see app.js) so the model and embeddings are ready before the first real request.
async function preload() {
  await getCategoryEmbeddings();
}

module.exports = { classifyByEmbedding, preload };

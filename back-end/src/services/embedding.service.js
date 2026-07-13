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

// Embeds the (already keyword-normalized) merchant text and returns the
// category description it's closest to, with the similarity score used
// directly as the confidence.
async function classifyByEmbedding(normalizedText) {
  const [textEmbedding, categoryEmbeddings] = await Promise.all([
    embed(normalizedText),
    getCategoryEmbeddings(),
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
  return { category: bestCategory, confidence: bestScore };
}

// Called once at server startup (see app.js) so the model is already
// downloaded/loaded and category embeddings are precomputed before the
// first real request arrives, instead of stalling that first request.
async function preload() {
  await getCategoryEmbeddings();
}

module.exports = { classifyByEmbedding, preload };

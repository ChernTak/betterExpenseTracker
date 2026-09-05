const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Same "regenerable artifact, not checked into git" convention as Tier B's
// model (see model.service.js) — ai/models/ is gitignored except .gitkeep.
const MODEL_PATH = path.join(__dirname, '..', '..', '..', 'ai', 'models', 'receipt_ner_model.tflite');

// Same hash-of-bytes-as-version approach as model.service.js, kept separate since this 153MB model streams to disk client-side instead of bundling as a Flutter asset.
let cachedVersion = null;
let cachedMtimeMs = null;

function computeVersion() {
  const stats = fs.statSync(MODEL_PATH);
  if (cachedVersion && cachedMtimeMs === stats.mtimeMs) {
    return cachedVersion;
  }
  const hash = crypto.createHash('sha256').update(fs.readFileSync(MODEL_PATH)).digest('hex');
  cachedVersion = hash;
  cachedMtimeMs = stats.mtimeMs;
  return hash;
}

// GET /api/ocr/model/version — the on-device receipt NER service compares
// this against its own last-downloaded version before fetching a fresh copy.
exports.getModelVersion = (req, res) => {
  try {
    return res.status(200).json({ version: computeVersion() });
  } catch (err) {
    if (err.code === 'ENOENT') {
      return res.status(404).json({ message: 'No receipt NER model available yet' });
    }
    console.error('Get receipt NER model version error', err);
    return res.status(500).json({ message: 'Failed to read model version', error: err.message });
  }
};

// createReadStream().pipe() is constant-memory regardless of file size; it's the client that must write straight to disk, not buffer the response.
exports.getModelFile = (req, res) => {
  if (!fs.existsSync(MODEL_PATH)) {
    return res.status(404).json({ message: 'No receipt NER model available yet' });
  }
  res.setHeader('Content-Type', 'application/octet-stream');
  fs.createReadStream(MODEL_PATH).pipe(res);
};

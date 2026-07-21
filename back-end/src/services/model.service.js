const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ai/ is a sibling of back-end/ at the repo root — this is the same
// "versioned source of truth" location ai/train_tier_b.py already writes
// to, so there's no separate copy to keep in sync here.
const MODEL_PATH = path.join(__dirname, '..', '..', '..', 'ai', 'models', 'tier_b_regressor.tflite');

// The model's "version" is just a hash of its own bytes — always accurate,
// no separate version-tracking file to forget to update. Cached against
// the file's mtime so a normal GET doesn't re-hash a multi-MB file every
// request; only recomputed after ai/train_tier_b.py actually writes a new one.
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

// GET /api/insights/model/version — front-end/lib/services/tier_b_inference_service.dart
// compares this against its own last-downloaded version before deciding
// whether to fetch a fresh copy.
exports.getModelVersion = (req, res) => {
  try {
    return res.status(200).json({ version: computeVersion() });
  } catch (err) {
    if (err.code === 'ENOENT') {
      return res.status(404).json({ message: 'No trained Tier B model available yet' });
    }
    console.error('Get model version error', err);
    return res.status(500).json({ message: 'Failed to read model version', error: err.message });
  }
};

// GET /api/insights/model/file — streams the current .tflite for the app
// to cache locally and load on-device (tflite_flutter's Interpreter.fromFile).
exports.getModelFile = (req, res) => {
  if (!fs.existsSync(MODEL_PATH)) {
    return res.status(404).json({ message: 'No trained Tier B model available yet' });
  }
  res.setHeader('Content-Type', 'application/octet-stream');
  fs.createReadStream(MODEL_PATH).pipe(res);
};

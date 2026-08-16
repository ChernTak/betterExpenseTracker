const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Same "regenerable artifact, not checked into git" convention as Tier B's
// model (see model.service.js) — ai/models/ is gitignored except .gitkeep.
const MODEL_PATH = path.join(__dirname, '..', '..', '..', 'ai', 'models', 'receipt_ner_model.tflite');

// Same hash-of-bytes-as-version, cached against mtime, as model.service.js —
// see that file's comment for the reasoning. Kept as a separate cache/module
// rather than parameterizing model.service.js, since this model (153MB) has
// a genuinely different delivery story client-side (streamed to disk, not
// bundled as a Flutter asset) even though the server-side logic mirrors it.
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

// GET /api/ocr/model/file — streams the current .tflite (153MB, vs. Tier
// B's 14KB) for the app to save to disk and load on-device. A plain
// createReadStream().pipe() is already a constant-memory stream regardless
// of file size, so no special handling is needed server-side for the size
// difference — it's the *client's* download that needs to write straight to
// disk instead of buffering the whole response in memory.
exports.getModelFile = (req, res) => {
  if (!fs.existsSync(MODEL_PATH)) {
    return res.status(404).json({ message: 'No receipt NER model available yet' });
  }
  res.setHeader('Content-Type', 'application/octet-stream');
  fs.createReadStream(MODEL_PATH).pipe(res);
};

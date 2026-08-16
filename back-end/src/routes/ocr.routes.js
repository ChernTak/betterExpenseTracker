const express = require('express');
const router = express.Router();
const ocrService = require('../services/ocr.service');
const receiptNerModelService = require('../services/receipt_ner_model.service');
const authMiddleware = require('../middleware/auth.middleware');

// All OCR routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.post('/parse', ocrService.parseReceipt);

// OTA delivery for the on-device receipt NER model (LayoutLMv3) — mirrors
// insight.routes.js's model/version + model/file pattern for Tier B.
router.get('/model/version', receiptNerModelService.getModelVersion);
router.get('/model/file', receiptNerModelService.getModelFile);

module.exports = router;

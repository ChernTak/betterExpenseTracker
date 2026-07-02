const express = require('express');
const router = express.Router();
const ocrService = require('../services/ocr.service');
const authMiddleware = require('../middleware/auth.middleware');

// All OCR routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.post('/parse', ocrService.parseReceipt);

module.exports = router;

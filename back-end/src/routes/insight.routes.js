const express = require('express');
const router = express.Router();
const forecastService = require('../services/forecast.service');
const modelService = require('../services/model.service');
const authMiddleware = require('../middleware/auth.middleware');

// All insight routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.get('/forecast', forecastService.getForecast);
router.post('/predictions', forecastService.logPrediction);
router.get('/model/version', modelService.getModelVersion);
router.get('/model/file', modelService.getModelFile);

module.exports = router;

const express = require('express');
const router = express.Router();
const configService = require('../services/config.service');

// Public — checked at app startup before we know a feature is safe to run,
// so it can't depend on a valid JWT being available.
router.get('/feature-flags', configService.getFeatureFlags);

module.exports = router;

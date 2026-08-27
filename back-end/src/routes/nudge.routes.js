const express = require('express');
const router = express.Router();
const nudgeService = require('../services/nudge.service');
const authMiddleware = require('../middleware/auth.middleware');

router.use(authMiddleware);

// GET /api/nudge/high-risk-locations — the Android app fetches this once
// (when background-location consent is granted) to register geofences.
router.get('/high-risk-locations', nudgeService.listHighRiskLocations);

// POST /api/nudge/location-entered — called by the Android side's native
// geofencing bridge when a registered geofence fires an ENTER transition.
router.post('/location-entered', nudgeService.handleLocationEntered);

module.exports = router;

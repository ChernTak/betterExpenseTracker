const express = require('express');
const router = express.Router();
const recommendationService = require('../services/recommendation.service');
const authMiddleware = require('../middleware/auth.middleware');

router.use(authMiddleware);

router.get('/food', recommendationService.getFoodRecommendations);
router.get('/food/venues/:provider/:providerPlaceId', recommendationService.getVenueDetail);

module.exports = router;

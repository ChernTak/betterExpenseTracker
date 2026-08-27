const express = require('express');
const router = express.Router();
const authService = require('../services/auth.service');
const authMiddleware = require('../middleware/auth.middleware');

router.post('/register', authService.register);
router.post('/login', authService.login);
router.post('/guest', authService.guestLogin);
router.post('/reset-password', authService.requestPasswordReset);
router.post('/reset-password/confirm', authService.confirmPasswordReset);
router.get('/me', authMiddleware, authService.getProfile);
router.put('/fcm-token', authMiddleware, authService.updateFcmToken);
router.put('/location-consent', authMiddleware, authService.updateLocationConsent);
router.put('/background-location-consent', authMiddleware, authService.updateBackgroundLocationConsent);

module.exports = router;

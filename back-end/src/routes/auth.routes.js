const express = require('express');
const router = express.Router();
const authService = require('../services/auth.service');
const authMiddleware = require('../middleware/auth.middleware');

router.post('/register', authService.register);
router.post('/login', authService.login);
router.post('/reset-password', authService.requestPasswordReset);
router.post('/reset-password/confirm', authService.confirmPasswordReset);
router.put('/fcm-token', authMiddleware, authService.updateFcmToken);

module.exports = router;

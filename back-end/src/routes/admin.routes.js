const express = require('express');
const router = express.Router();
const adminService = require('../services/admin.service');
const authMiddleware = require('../middleware/auth.middleware');
const requireAdmin = require('../middleware/admin.middleware');

// FR1.7 / NFR 3.4 — every route below requires a valid JWT belonging to an
// admin-role account.
router.use(authMiddleware);
router.use(requireAdmin);

router.get('/users', adminService.listUsers);
router.get('/users/:userId', adminService.getUser);
router.patch('/users/:userId/deactivate', adminService.deactivateUser);
router.patch('/users/:userId/reactivate', adminService.reactivateUser);
router.delete('/users/:userId', adminService.deleteUser);
router.patch('/users/:userId/cancel-deletion', adminService.cancelDeletion);
router.delete('/users/:userId/purge', adminService.purgeUser);
router.get('/users/:userId/export', adminService.exportUserData);
router.get('/users/:userId/consent-history', adminService.getConsentHistory);
router.get('/audit-log', adminService.getAuditLog);
router.delete('/recommendation-logs/purge', adminService.purgeRecommendationLogs);
router.delete('/guests/purge', adminService.purgeStaleGuests);
router.delete('/venue-cache/purge', adminService.purgeVenueCache);
router.delete('/photo-cache/purge', adminService.purgePhotoCache);

module.exports = router;

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

module.exports = router;

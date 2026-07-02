const express = require('express');
const router = express.Router();
const budgetService = require('../services/budget.service');
const authMiddleware = require('../middleware/auth.middleware');

// All budget routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.post('/', budgetService.createBudget);
router.get('/', budgetService.listBudgets);
router.get('/alerts', budgetService.listRecentAlerts);
router.put('/:id', budgetService.updateBudget);
router.delete('/:id', budgetService.deleteBudget);

module.exports = router;

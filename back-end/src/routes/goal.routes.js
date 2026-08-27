const express = require('express');
const router = express.Router();
const goalService = require('../services/goal.service');
const authMiddleware = require('../middleware/auth.middleware');

// All goal routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.post('/', goalService.createGoal);
router.get('/', goalService.listGoals);
router.put('/:id', goalService.updateGoal);
router.delete('/:id', goalService.deleteGoal);

router.get('/:id/contributions', goalService.listContributions);
router.post('/:id/contributions', goalService.addContribution);

module.exports = router;

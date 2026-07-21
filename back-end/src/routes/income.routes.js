const express = require('express');
const router = express.Router();
const incomeService = require('../services/income.service');
const authMiddleware = require('../middleware/auth.middleware');

// All income routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.post('/', incomeService.logIncome);
router.get('/', incomeService.listIncome);
router.put('/:id', incomeService.updateIncome);
router.delete('/:id', incomeService.deleteIncome);

module.exports = router;

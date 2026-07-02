const express = require('express');
const router = express.Router();
const expenseService = require('../services/expense.service');
const authMiddleware = require('../middleware/auth.middleware');

// All expense routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

//Link the POST action to the backend handler service function
router.post('/post', expenseService.postData);
router.get('/fetch', expenseService.fetchData);
router.get('/:id', expenseService.fetchById);
router.put('/update/:id', expenseService.updateData);
router.delete('/delete/:id', expenseService.deleteData);

module.exports = router;
const express = require('express');
const router = express.Router();
const categoryService = require('../services/category.service');
const authMiddleware = require('../middleware/auth.middleware');

// All category routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.get('/', categoryService.list);
router.post('/', categoryService.create);
router.put('/reorder', categoryService.reorder);
router.put('/:id', categoryService.update);
router.delete('/:id', categoryService.remove);

module.exports = router;

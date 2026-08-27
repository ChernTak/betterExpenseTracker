const express = require('express');
const router = express.Router();
const wishlistService = require('../services/wishlist.service');
const authMiddleware = require('../middleware/auth.middleware');

// All wishlist routes require a valid JWT — req.user is set by the middleware
router.use(authMiddleware);

router.post('/', wishlistService.createWishlistItem);
router.get('/', wishlistService.listWishlist);
router.put('/:id', wishlistService.updateWishlistItem);
router.post('/:id/convert-to-goal', wishlistService.convertToGoal);
router.delete('/:id', wishlistService.deleteWishlistItem);

module.exports = router;

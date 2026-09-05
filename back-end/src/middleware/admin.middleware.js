// NFR 3.4 RBAC: must run after auth.middleware, which populates req.user.
module.exports = (req, res, next) => {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Admin access required' });
  }
  next();
};

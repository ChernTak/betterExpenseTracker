// NFR 3.4 — role-based access control: admin-only endpoints must reject
// regular users even with a valid JWT. Must run after auth.middleware
// (which populates req.user from the token payload).
module.exports = (req, res, next) => {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Admin access required' });
  }
  next();
};

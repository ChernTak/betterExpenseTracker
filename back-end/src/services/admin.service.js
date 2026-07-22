const userModel = require('../models/user.model');

// FR1.7 — "The system shall allow the administrator to view ... user
// accounts. This function is strictly reserved for complying with user data
// deletion requests (Privacy Rights) and mitigating security threats."
exports.listUsers = async (req, res) => {
  try {
    const result = await userModel.findAllForAdmin();
    return res.status(200).json({ users: result.rows });
  } catch (err) {
    console.error('Admin list users error', err);
    return res.status(500).json({ message: 'Failed to load users', error: err.message });
  }
};

exports.getUser = async (req, res) => {
  try {
    const result = await userModel.findByIdForAdmin(req.params.userId);
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    return res.status(200).json({ user: result.rows[0] });
  } catch (err) {
    console.error('Admin get user error', err);
    return res.status(500).json({ message: 'Failed to load user', error: err.message });
  }
};

// FR1.7 — deactivate. Reversible: a deactivated account cannot log in
// (see auth.service.js) but its data is preserved.
exports.deactivateUser = async (req, res) => {
  const { userId } = req.params;

  if (userId === req.user.userId) {
    return res.status(400).json({ message: 'An admin cannot deactivate their own account' });
  }

  try {
    const existing = await userModel.findByIdForAdmin(userId);
    if (existing.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    const result = await userModel.setActiveStatus(userId, false);
    return res.status(200).json({ message: 'User account deactivated', user: result.rows[0] });
  } catch (err) {
    console.error('Admin deactivate user error', err);
    return res.status(500).json({ message: 'Failed to deactivate user', error: err.message });
  }
};

// Symmetric counterpart to deactivation — restores login access without
// requiring a destructive delete-and-recreate cycle.
exports.reactivateUser = async (req, res) => {
  const { userId } = req.params;

  try {
    const existing = await userModel.findByIdForAdmin(userId);
    if (existing.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    const result = await userModel.setActiveStatus(userId, true);
    return res.status(200).json({ message: 'User account reactivated', user: result.rows[0] });
  } catch (err) {
    console.error('Admin reactivate user error', err);
    return res.status(500).json({ message: 'Failed to reactivate user', error: err.message });
  }
};

// FR1.7 — delete. Permanent; every other table's user_id FK cascades
// (see 024_admin_user_management.sql migration note), satisfying PDPA
// data-deletion requests in a single statement.
exports.deleteUser = async (req, res) => {
  const { userId } = req.params;

  if (userId === req.user.userId) {
    return res.status(400).json({ message: 'An admin cannot delete their own account' });
  }

  try {
    const result = await userModel.deleteUser(userId);
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    return res.status(200).json({ message: 'User account permanently deleted', user: result.rows[0] });
  } catch (err) {
    console.error('Admin delete user error', err);
    return res.status(500).json({ message: 'Failed to delete user', error: err.message });
  }
};

const db = require('../config/db');
const userModel = require('../models/user.model');
const auditLogModel = require('../models/auditLog.model');
const consentLogModel = require('../models/consentLog.model');
const recommendationModel = require('../models/recommendation.model');

const DELETION_GRACE_DAYS = Number(process.env.ADMIN_DELETION_GRACE_DAYS) || 14;

// PDPA accountability — every admin action against a user record goes
// through here so it always lands in admin_audit_log, even if a caller
// forgets. Failures are logged but never block the actual admin action.
const logAdminAction = async (req, action, target, details) => {
  try {
    await auditLogModel.insert({
      adminId: req.user.userId,
      action,
      targetUserId: target ? target.user_id : null,
      targetEmail: target ? target.email : null,
      details,
    });
  } catch (err) {
    console.error('Failed to write admin audit log entry', err);
  }
};

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

// PDPA data-minimization — the list view masks mobile_number; this is the
// only view that returns it in full, so every call is audit-logged as a
// deliberate "view profile" action.
exports.getUser = async (req, res) => {
  try {
    const result = await userModel.findByIdForAdmin(req.params.userId);
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    await logAdminAction(req, 'view_profile', result.rows[0]);
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
    await logAdminAction(req, 'deactivate', result.rows[0]);
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
    await logAdminAction(req, 'reactivate', result.rows[0]);
    return res.status(200).json({ message: 'User account reactivated', user: result.rows[0] });
  } catch (err) {
    console.error('Admin reactivate user error', err);
    return res.status(500).json({ message: 'Failed to reactivate user', error: err.message });
  }
};

// FR1.7 — delete request. PDPA erasure with a recoverability window: this
// soft-deletes (deactivates + timestamps the request) rather than deleting
// outright, so an accidental or malicious click isn't instantly
// unrecoverable. The row is only permanently removed by purgeUser below,
// once the grace period has elapsed.
exports.deleteUser = async (req, res) => {
  const { userId } = req.params;

  if (userId === req.user.userId) {
    return res.status(400).json({ message: 'An admin cannot delete their own account' });
  }

  try {
    const existing = await userModel.findByIdForAdmin(userId);
    if (existing.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    const result = await userModel.requestDeletion(userId);
    await logAdminAction(req, 'request_deletion', result.rows[0], { graceDays: DELETION_GRACE_DAYS });
    return res.status(200).json({ message: 'Deletion requested; account deactivated pending purge', user: result.rows[0] });
  } catch (err) {
    console.error('Admin request deletion error', err);
    return res.status(500).json({ message: 'Failed to request deletion', error: err.message });
  }
};

// Reverses a pending deletion request within the grace window.
exports.cancelDeletion = async (req, res) => {
  const { userId } = req.params;

  try {
    const existing = await userModel.findByIdForAdmin(userId);
    if (existing.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    if (!existing.rows[0].deletion_requested_at) {
      return res.status(400).json({ message: 'This user has no pending deletion request' });
    }

    const result = await userModel.cancelDeletionRequest(userId);
    await logAdminAction(req, 'cancel_deletion', result.rows[0]);
    return res.status(200).json({ message: 'Deletion request cancelled', user: result.rows[0] });
  } catch (err) {
    console.error('Admin cancel deletion error', err);
    return res.status(500).json({ message: 'Failed to cancel deletion request', error: err.message });
  }
};

// Permanent purge — every other table's user_id FK cascades (see
// 024_admin_user_management.sql migration note), satisfying PDPA
// data-deletion requests in a single statement. Blocked until
// ADMIN_DELETION_GRACE_DAYS has passed since deleteUser's request, unless
// explicitly forced (?force=true), since some requests do need to be
// honoured immediately.
exports.purgeUser = async (req, res) => {
  const { userId } = req.params;
  const force = req.query.force === 'true';

  if (userId === req.user.userId) {
    return res.status(400).json({ message: 'An admin cannot delete their own account' });
  }

  try {
    const existing = await userModel.findByIdForAdmin(userId);
    if (existing.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    const target = existing.rows[0];
    if (!target.deletion_requested_at) {
      return res.status(400).json({ message: 'This user has no pending deletion request. Request deletion first.' });
    }

    const requestedAt = new Date(target.deletion_requested_at);
    const graceElapsedMs = Date.now() - requestedAt.getTime();
    const graceElapsed = graceElapsedMs >= DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000;

    if (!graceElapsed && !force) {
      const daysLeft = Math.ceil((DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000 - graceElapsedMs) / (24 * 60 * 60 * 1000));
      return res.status(400).json({
        message: `Grace period has not elapsed (${daysLeft} day(s) remaining). Pass ?force=true to purge immediately.`,
      });
    }

    // Logged before the row is gone — afterwards target_user_id FK nulls out,
    // but target_email survives as the record of what was purged and why.
    await logAdminAction(req, 'purge_user', target, { forced: !graceElapsed && force });

    const result = await userModel.deleteUser(userId);
    return res.status(200).json({ message: 'User account permanently deleted', user: result.rows[0] });
  } catch (err) {
    console.error('Admin purge user error', err);
    return res.status(500).json({ message: 'Failed to purge user', error: err.message });
  }
};

// PDPA Access principle — lets an admin fulfil a data subject access
// request by pulling everything the app holds on one user in a single
// downloadable JSON payload.
exports.exportUserData = async (req, res) => {
  const { userId } = req.params;

  try {
    const userResult = await userModel.findByIdForAdmin(userId);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    const profile = userResult.rows[0];

    const [expenses, budgets, savingGoals, wishlist, ocrReceipts, recommendationLogs, incomeLog, consentHistory] =
      await Promise.all([
        db.query('SELECT * FROM expenses WHERE user_id = $1', [userId]),
        db.query('SELECT * FROM budgets WHERE user_id = $1', [userId]),
        db.query('SELECT * FROM saving_goals WHERE user_id = $1', [userId]),
        db.query('SELECT * FROM wishlist WHERE user_id = $1', [userId]),
        db.query('SELECT * FROM ocr_receipts WHERE user_id = $1', [userId]),
        db.query('SELECT * FROM recommendation_log WHERE user_id = $1', [userId]),
        db.query('SELECT * FROM income_log WHERE user_id = $1', [userId]),
        consentLogModel.findForUser(userId),
      ]);

    await logAdminAction(req, 'export_data', profile, {
      recordCounts: {
        expenses: expenses.rows.length,
        budgets: budgets.rows.length,
        savingGoals: savingGoals.rows.length,
        wishlist: wishlist.rows.length,
        ocrReceipts: ocrReceipts.rows.length,
        recommendationLogs: recommendationLogs.rows.length,
        incomeLog: incomeLog.rows.length,
        consentHistory: consentHistory.rows.length,
      },
    });

    const exportPayload = {
      profile,
      expenses: expenses.rows,
      budgets: budgets.rows,
      savingGoals: savingGoals.rows,
      wishlist: wishlist.rows,
      ocrReceipts: ocrReceipts.rows,
      recommendationLogs: recommendationLogs.rows,
      incomeLog: incomeLog.rows,
      consentHistory: consentHistory.rows,
      exportedAt: new Date().toISOString(),
    };

    res.setHeader('Content-Disposition', `attachment; filename="user-${userId}-export.json"`);
    return res.status(200).json(exportPayload);
  } catch (err) {
    console.error('Admin export user data error', err);
    return res.status(500).json({ message: 'Failed to export user data', error: err.message });
  }
};

// PDPA Notice & Choice — evidence of when this user granted/withdrew consent.
exports.getConsentHistory = async (req, res) => {
  try {
    const result = await consentLogModel.findForUser(req.params.userId);
    return res.status(200).json({ consentHistory: result.rows });
  } catch (err) {
    console.error('Admin get consent history error', err);
    return res.status(500).json({ message: 'Failed to load consent history', error: err.message });
  }
};

// PDPA Accountability — the audit trail itself, for the admin panel.
exports.getAuditLog = async (req, res) => {
  try {
    const result = await auditLogModel.findRecent(200);
    return res.status(200).json({ auditLog: result.rows });
  } catch (err) {
    console.error('Admin get audit log error', err);
    return res.status(500).json({ message: 'Failed to load audit log', error: err.message });
  }
};

// PDPA data-minimization / retention — recommendation_log.context_snapshot
// carries raw GPS coordinates (see recommendation.service.js) that have no
// business reason to be kept indefinitely. Admin-triggered since this app
// has no job scheduler to run it automatically.
exports.purgeRecommendationLogs = async (req, res) => {
  const olderThanDays = Number(req.query.olderThanDays);
  if (!Number.isFinite(olderThanDays) || olderThanDays < 0) {
    return res.status(400).json({ message: 'olderThanDays must be a non-negative number' });
  }

  try {
    const result = await recommendationModel.purgeOlderThan(olderThanDays);
    await logAdminAction(req, 'purge_recommendation_logs', null, {
      olderThanDays,
      deletedCount: result.rows.length,
    });
    return res.status(200).json({ message: 'Old recommendation logs purged', deletedCount: result.rows.length });
  } catch (err) {
    console.error('Admin purge recommendation logs error', err);
    return res.status(500).json({ message: 'Failed to purge recommendation logs', error: err.message });
  }
};

// PDPA storage-limitation — "Continue as Guest" mints a new users row every
// time with no reuse and no session resume on the client (see
// user.model.js purgeStaleGuests), so abandoned guest rows accumulate with
// no ongoing purpose. Unlike purgeRecommendationLogs this deletes
// identities, not just log rows, so the audit entry lists which emails were
// purged rather than only a count.
exports.purgeStaleGuests = async (req, res) => {
  const olderThanDays = Number(req.query.olderThanDays);
  if (!Number.isFinite(olderThanDays) || olderThanDays < 0) {
    return res.status(400).json({ message: 'olderThanDays must be a non-negative number' });
  }

  try {
    const result = await userModel.purgeStaleGuests(olderThanDays);
    const purgedEmails = result.rows.map((row) => row.email);
    await logAdminAction(req, 'purge_stale_guests', null, {
      olderThanDays,
      deletedCount: result.rows.length,
      purgedEmails,
    });
    return res.status(200).json({ message: 'Stale guest accounts purged', deletedCount: result.rows.length });
  } catch (err) {
    console.error('Admin purge stale guests error', err);
    return res.status(500).json({ message: 'Failed to purge stale guest accounts', error: err.message });
  }
};

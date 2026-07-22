const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const userModel = require('../models/user.model');
const categoryModel = require('../models/category.model');
const passwordResetModel = require('../models/passwordReset.model');
const { sendPasswordResetEmail } = require('../utils/mailer');

const SALT_ROUNDS = 12;

// FR1.1 — 8+ chars, at least one uppercase, one lowercase, one number
function isValidPassword(password) {
  return (
    typeof password === 'string' &&
    password.length >= 8 &&
    /[A-Z]/.test(password) &&
    /[a-z]/.test(password) &&
    /[0-9]/.test(password)
  );
}

async function triggerPasswordResetEmail(user) {
  const rawToken = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

  await passwordResetModel.createToken(user.user_id, tokenHash, expiresAt);
  await sendPasswordResetEmail(user.email, rawToken);
}

exports.register = async (req, res) => {
  const { email, username, password, mobileNumber } = req.body;

  if (!email || !username || !password) {
    return res.status(400).json({ message: 'email, username and password are required' });
  }
  if (!isValidPassword(password)) {
    return res.status(400).json({
      message: 'Password must be at least 8 characters and include an uppercase letter, a lowercase letter and a number',
    });
  }

  try {
    const existing = await userModel.findByEmail(email);
    if (existing.rows.length > 0) {
      return res.status(409).json({ message: 'Email already registered' });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    const result = await userModel.createUser({ email, username, passwordHash, mobileNumber });
    await categoryModel.seedDefaultsForUser(result.rows[0].user_id);

    return res.status(201).json({
      message: 'Registration successful',
      user: result.rows[0],
    });
  } catch (err) {
    console.error('Register error', err);
    return res.status(500).json({ message: 'Registration failed', error: err.message });
  }
};

// "Continue as Guest" — skips the registration form entirely by creating a
// throwaway account behind the scenes and logging straight into it, so the
// rest of the app (which expects a real JWT/user_id everywhere) needs no
// special-casing for guests.
exports.guestLogin = async (req, res) => {
  try {
    const suffix = crypto.randomBytes(6).toString('hex');
    const email = `guest_${suffix}@guest.local`;
    const username = `Guest${suffix.slice(0, 6)}`;
    const passwordHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), SALT_ROUNDS);

    const result = await userModel.createGuestUser({ email, username, passwordHash });
    const user = result.rows[0];
    await categoryModel.seedDefaultsForUser(user.user_id);

    const token = jwt.sign(
      { userId: user.user_id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    return res.status(200).json({
      message: 'Continuing as guest',
      token,
      user: {
        userId: user.user_id,
        email: user.email,
        username: user.username,
        role: user.role,
        isGuest: true,
      },
    });
  } catch (err) {
    console.error('Guest login error', err);
    return res.status(500).json({ message: 'Failed to continue as guest', error: err.message });
  }
};

exports.login = async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ message: 'email and password are required' });
  }

  try {
    const result = await userModel.findByEmail(email);
    const user = result.rows[0];

    if (!user) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    // FR1.7 — an admin-deactivated account is refused outright, distinct
    // from the self-clearing is_locked state below.
    if (!user.is_active) {
      return res.status(403).json({ message: 'This account has been deactivated. Contact support for assistance.' });
    }

    // Auto-unlock once the 30-minute lockout window has passed
    if (user.is_locked && user.locked_until && new Date(user.locked_until) <= new Date()) {
      await userModel.resetFailedLogin(user.user_id);
      user.is_locked = false;
    }

    if (user.is_locked) {
      return res.status(423).json({
        message: 'Account locked. Check your email for a password reset link.',
      });
    }

    const passwordMatches = await bcrypt.compare(password, user.password_hash);

    if (!passwordMatches) {
      const updated = await userModel.incrementFailedLogin(user.user_id);
      const failInfo = updated.rows[0];

      // FR1.4 — 5th failure locks the account and auto-sends a reset link
      if (failInfo.is_locked) {
        await triggerPasswordResetEmail(user);
        return res.status(423).json({
          message: 'Account locked after 5 failed attempts. A password reset link has been sent to your email.',
        });
      }

      return res.status(401).json({ message: 'Invalid email or password' });
    }

    await userModel.resetFailedLogin(user.user_id);

    const token = jwt.sign(
      { userId: user.user_id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    return res.status(200).json({
      message: 'Login successful',
      token,
      user: {
        userId: user.user_id,
        email: user.email,
        username: user.username,
        role: user.role,
      },
    });
  } catch (err) {
    console.error('Login error', err);
    return res.status(500).json({ message: 'Login failed', error: err.message });
  }
};

// Called once the Flutter app obtains an FCM registration token, so the
// budget alert engine (FR3.5) has somewhere to deliver push notifications.
exports.updateFcmToken = async (req, res) => {
  const { fcmToken } = req.body;
  if (!fcmToken) {
    return res.status(400).json({ message: 'fcmToken is required' });
  }

  try {
    await userModel.updateFcmToken(req.user.userId, fcmToken);
    return res.status(200).json({ message: 'FCM token updated' });
  } catch (err) {
    console.error('Update FCM token error', err);
    return res.status(500).json({ message: 'Failed to update FCM token', error: err.message });
  }
};

// FR1.8 — request a time-limited reset link
exports.requestPasswordReset = async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ message: 'email is required' });
  }

  try {
    const result = await userModel.findByEmail(email);
    const user = result.rows[0];

    // Always return the same response whether or not the email exists,
    // so callers can't use this endpoint to enumerate registered emails.
    if (user) {
      await triggerPasswordResetEmail(user);
    }

    return res.status(200).json({ message: 'If that email is registered, a reset link has been sent.' });
  } catch (err) {
    console.error('Request password reset error', err);
    return res.status(500).json({ message: 'Failed to process request', error: err.message });
  }
};

// FR1.8 — consume the token from the emailed link and set a new password
exports.confirmPasswordReset = async (req, res) => {
  const { token, newPassword } = req.body;

  if (!token || !newPassword) {
    return res.status(400).json({ message: 'token and newPassword are required' });
  }
  if (!isValidPassword(newPassword)) {
    return res.status(400).json({
      message: 'Password must be at least 8 characters and include an uppercase letter, a lowercase letter and a number',
    });
  }

  try {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const result = await passwordResetModel.findValidToken(tokenHash);
    const resetRecord = result.rows[0];

    if (!resetRecord) {
      return res.status(400).json({ message: 'Invalid or expired reset token' });
    }

    const passwordHash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await userModel.updatePasswordHash(resetRecord.user_id, passwordHash);
    await userModel.resetFailedLogin(resetRecord.user_id);
    await passwordResetModel.markUsed(resetRecord.token_id);

    return res.status(200).json({ message: 'Password reset successful' });
  } catch (err) {
    console.error('Confirm password reset error', err);
    return res.status(500).json({ message: 'Failed to reset password', error: err.message });
  }
};

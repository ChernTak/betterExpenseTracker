const { getMessaging } = require('firebase-admin/messaging');
const { app, isConfigured } = require('../config/firebase');

// FCM push delivery for budget alerts (FR3.5). Mirrors utils/mailer.js: if
// Firebase isn't configured (or the user has no token yet), log instead of
// throwing so the request that triggered the alert still succeeds (NFR 4.3).
exports.sendPushNotification = async (fcmToken, { title, body, data }) => {
  if (!isConfigured || !fcmToken) {
    console.log(`[DEV] Push notification for token=${fcmToken || 'none'}: ${title} — ${body}`);
    return;
  }

  try {
    await getMessaging(app).send({
      token: fcmToken,
      notification: { title, body },
      // FCM data payloads must be flat string maps
      data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
    });
  } catch (err) {
    // A dead/expired token shouldn't fail the request that triggered the alert
    console.error('FCM send failed', err.message);
  }
};

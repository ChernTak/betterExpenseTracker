const { getMessaging } = require('firebase-admin/messaging');
const { app, isConfigured } = require('../config/firebase');

// FCM push for budget alerts; if unconfigured or no token, log instead of throwing so the triggering request still succeeds.
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

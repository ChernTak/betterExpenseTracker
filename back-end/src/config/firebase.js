const { initializeApp, cert, getApps } = require('firebase-admin/app');

const projectId = process.env.FIREBASE_PROJECT_ID;
const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
const privateKey = process.env.FIREBASE_PRIVATE_KEY;

// Optional in dev, same pattern as utils/mailer.js's SMTP fallback — if unset,
// pushNotifier.js logs the notification instead of sending it (NFR 4.3).
const isConfigured = Boolean(projectId && clientEmail && privateKey);

// firebase-admin v13+ uses the modular API (initializeApp/cert from
// 'firebase-admin/app'), not the old admin.credential.cert() namespace.
let app = null;
if (isConfigured) {
  app = getApps().length
    ? getApps()[0]
    : initializeApp({
        credential: cert({
          projectId,
          clientEmail,
          privateKey: privateKey.replace(/\\n/g, '\n'),
        }),
      });
} else {
  console.log('[DEV] Firebase Admin not configured — push notifications will be logged, not sent.');
}

module.exports = { app, isConfigured };

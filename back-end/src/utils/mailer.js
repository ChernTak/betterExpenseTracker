const nodemailer = require('nodemailer');

const smtpConfigured = process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS;

const transporter = smtpConfigured
  ? nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT) || 587,
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    })
  : null;

exports.sendPasswordResetEmail = async (toEmail, rawToken) => {
  const resetLink = `${process.env.FRONTEND_RESET_URL || 'http://localhost:3000/reset-password'}?token=${rawToken}`;

  if (!transporter) {
    // No SMTP configured in .env — log the link so the flow is testable in dev
    console.log(`[DEV] Password reset link for ${toEmail}: ${resetLink}`);
    return;
  }

  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: toEmail,
    subject: 'Reset your AI Personal Finance System password',
    text: `Click this link to reset your password (expires in 15 minutes): ${resetLink}`,
  });
};

const nodemailer = require('nodemailer');

let transporter;

const hasMailCredentials = () =>
  !!(
    process.env.MAIL_HOST &&
    process.env.MAIL_PORT &&
    process.env.MAIL_USER &&
    process.env.MAIL_PASS
  );

const getTransporter = () => {
  if (transporter) {
    return transporter;
  }

  if (!hasMailCredentials()) {
    throw new Error('Email credentials are not configured');
  }

  transporter = nodemailer.createTransport({
    host: process.env.MAIL_HOST,
    port: Number(process.env.MAIL_PORT || 587),
    secure: process.env.MAIL_SECURE === 'true',
    auth: {
      user: process.env.MAIL_USER,
      pass: process.env.MAIL_PASS,
    },
  });

  return transporter;
};

const buildResetLink = (token) => {
  const base = process.env.PASSWORD_RESET_URL || process.env.APP_URL;
  if (!base) {
    return `https://moodiary.app/reset-password?token=${token}`;
  }

  const separator = base.includes('?') ? '&' : '?';
  return `${base}${separator}token=${token}`;
};

async function sendPasswordResetEmail({ to, name, token }) {
  const resetLink = buildResetLink(token);

  if (!hasMailCredentials()) {
    console.warn(
      'Password reset requested but MAIL_* env vars are missing. Link:',
      resetLink
    );
    return { delivered: false, previewUrl: resetLink };
  }

  const mailer = getTransporter();

  await mailer.sendMail({
    from: process.env.MAIL_FROM || 'Moodiary <no-reply@moodiary.app>',
    to,
    subject: 'Reset your Moodiary password',
    html: `
      <p>Hi ${name || 'there'},</p>
      <p>We received a request to reset the password for your Moodiary account.</p>
      <p><a href="${resetLink}" style="padding:12px 20px;background:#6C63FF;color:#fff;text-decoration:none;border-radius:4px;display:inline-block">Reset password</a></p>
      <p>This link will expire in 60 minutes. If you did not request a reset, you can safely ignore this email.</p>
    `,
  });

  return { delivered: true, previewUrl: resetLink };
}

module.exports = {
  sendPasswordResetEmail,
};

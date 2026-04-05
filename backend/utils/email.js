const nodemailer = require('nodemailer');

let transporter;
const MAIL_SEND_TIMEOUT_MS = Number(process.env.MAIL_SEND_TIMEOUT_MS || 15000);

const readEnv = (keys) => {
  for (const key of keys) {
    const value = process.env[key];
    if (typeof value === 'string' && value.trim()) {
      return value.trim();
    }
  }
  return '';
};

const isGmailAccount = (email) => /@gmail\.com$/i.test(email);

const getMailConfig = () => {
  const user = readEnv(['MAIL_USER', 'GMAIL_USER']);
  const pass = readEnv(['MAIL_PASS', 'GMAIL_APP_PASSWORD']);
  const service = readEnv(['MAIL_SERVICE']);
  const host = readEnv(['MAIL_HOST']);
  const port = Number(readEnv(['MAIL_PORT']) || 587);
  const secureEnv = readEnv(['MAIL_SECURE']);
  const from = readEnv(['MAIL_FROM']);

  if (!user || !pass) {
    return null;
  }

  if (service) {
    return {
      transport: {
        service,
        connectionTimeout: MAIL_SEND_TIMEOUT_MS,
        greetingTimeout: MAIL_SEND_TIMEOUT_MS,
        socketTimeout: MAIL_SEND_TIMEOUT_MS,
        auth: { user, pass },
      },
      from: from || `Moodiary <${user}>`,
    };
  }

  if (host) {
    return {
      transport: {
        host,
        port,
        secure:
          secureEnv === 'true' || (secureEnv === '' && port === 465),
        connectionTimeout: MAIL_SEND_TIMEOUT_MS,
        greetingTimeout: MAIL_SEND_TIMEOUT_MS,
        socketTimeout: MAIL_SEND_TIMEOUT_MS,
        auth: { user, pass },
      },
      from: from || `Moodiary <${user}>`,
    };
  }

  if (isGmailAccount(user)) {
    return {
      transport: {
        service: 'gmail',
        connectionTimeout: MAIL_SEND_TIMEOUT_MS,
        greetingTimeout: MAIL_SEND_TIMEOUT_MS,
        socketTimeout: MAIL_SEND_TIMEOUT_MS,
        auth: { user, pass },
      },
      from: from || `Moodiary <${user}>`,
    };
  }

  return null;
};

const getTransporter = () => {
  if (transporter) {
    return transporter;
  }

  const config = getMailConfig();
  if (!config) {
    throw new Error(
      'Email credentials are not configured. Set MAIL_SERVICE=gmail and provide MAIL_USER/MAIL_PASS, or configure MAIL_HOST/MAIL_PORT.'
    );
  }

  transporter = nodemailer.createTransport(config.transport);

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

  const mailer = getTransporter();
  const config = getMailConfig();
  const from = config?.from || 'Moodiary <no-reply@moodiary.app>';

  const mailTask = mailer.sendMail({
    from,
    to,
    subject: 'Reset your Moodiary password',
    html: `
      <p>Hi ${name || 'there'},</p>
      <p>We received a request to reset the password for your Moodiary account.</p>
      <p><a href="${resetLink}" style="padding:12px 20px;background:#6C63FF;color:#fff;text-decoration:none;border-radius:4px;display:inline-block">Reset password</a></p>
      <p>If the button does not open, copy this token into the Moodiary app:</p>
      <p style="font-family:monospace;background:#f3f4f6;padding:12px;border-radius:6px;word-break:break-all">${token}</p>
      <p>This link will expire in 60 minutes. If you did not request a reset, you can safely ignore this email.</p>
    `,
  });

  const timeoutTask = new Promise((_, reject) => {
    setTimeout(
      () => reject(new Error('Email send timed out. Please try again.')),
      MAIL_SEND_TIMEOUT_MS
    );
  });

  await Promise.race([mailTask, timeoutTask]);

  return { delivered: true, previewUrl: resetLink };
}

module.exports = {
  sendPasswordResetEmail,
};

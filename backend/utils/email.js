const nodemailer = require('nodemailer');

let transporter;
const MAIL_SEND_TIMEOUT_MS = Number(process.env.MAIL_SEND_TIMEOUT_MS || 15000);
const RESEND_API_URL = 'https://api.resend.com/emails';

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

const normalizeMailPassword = ({ user, service, pass }) => {
  const isGmail = service === 'gmail' || isGmailAccount(user);
  if (!isGmail) return pass;
  // Google displays app passwords in grouped chunks; pasted values may contain spaces.
  return pass.replace(/\s+/g, '');
};

const getMailConfig = () => {
  const user = readEnv(['MAIL_USER', 'GMAIL_USER']);
  const rawPass = readEnv(['MAIL_PASS', 'GMAIL_APP_PASSWORD']);
  const service = readEnv(['MAIL_SERVICE']).toLowerCase();
  const host = readEnv(['MAIL_HOST']);
  const port = Number(readEnv(['MAIL_PORT']) || 587);
  const secureEnv = readEnv(['MAIL_SECURE']);
  const from = readEnv(['MAIL_FROM']);
  const pass = normalizeMailPassword({ user, service, pass: rawPass });

  if (!user || !pass) {
    return null;
  }

  if (service === 'gmail') {
    const gmailPort = Number(readEnv(['MAIL_PORT']) || 465);
    const gmailSecure =
      secureEnv === 'true' || (secureEnv === '' && gmailPort === 465);
    return {
      transport: {
        host: 'smtp.gmail.com',
        port: gmailPort,
        secure: gmailSecure,
        requireTLS: !gmailSecure,
        connectionTimeout: MAIL_SEND_TIMEOUT_MS,
        greetingTimeout: MAIL_SEND_TIMEOUT_MS,
        socketTimeout: MAIL_SEND_TIMEOUT_MS,
        auth: { user, pass },
      },
      from: from || `Moodiary <${user}>`,
    };
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
    const gmailPort = Number(readEnv(['MAIL_PORT']) || 465);
    const gmailSecure =
      secureEnv === 'true' || (secureEnv === '' && gmailPort === 465);
    return {
      transport: {
        host: 'smtp.gmail.com',
        port: gmailPort,
        secure: gmailSecure,
        requireTLS: !gmailSecure,
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

const buildResetHtml = ({ name, code }) => `
  <p>Hi ${name || 'there'},</p>
  <p>We received a request to reset the password for your Moodiary account.</p>
  <p>Use this verification code in the app to continue:</p>
  <p style="font-family:monospace;background:#f3f4f6;padding:12px;border-radius:6px;word-break:break-all;font-size:20px;letter-spacing:0.2em">${code}</p>
  <p>This code will expire in 10 minutes. If you did not request a reset, you can safely ignore this email.</p>
`;

const getResendConfig = () => {
  const apiKey = readEnv(['RESEND_API_KEY']);
  const from = readEnv(['MAIL_FROM']) || 'Moodiary <no-reply@moodiary.app>';
  if (!apiKey) return null;
  return { apiKey, from };
};

async function sendViaResendApi({ to, resendConfig, html }) {
  if (typeof fetch !== 'function') {
    throw new Error('Fetch API is unavailable in current Node runtime');
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), MAIL_SEND_TIMEOUT_MS);

  try {
    const response = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendConfig.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: resendConfig.from,
        to: [to],
        subject: 'Reset your Moodiary password',
        html,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const details = await response.text();
      throw new Error(`Resend API failed (${response.status}): ${details}`);
    }
  } catch (error) {
    if (error && error.name === 'AbortError') {
      throw new Error('Email send timed out. Please try again.');
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

async function sendPasswordResetEmail({ to, name, code }) {
  const html = buildResetHtml({ name, code });

  const resendConfig = getResendConfig();
  if (resendConfig) {
    await sendViaResendApi({ to, resendConfig, html });
    return { delivered: true, provider: 'resend' };
  }

  const mailer = getTransporter();
  const config = getMailConfig();
  const from = config?.from || 'Moodiary <no-reply@moodiary.app>';

  const mailTask = mailer.sendMail({
    from,
    to,
    subject: 'Reset your Moodiary password',
    html,
  });

  const timeoutTask = new Promise((_, reject) => {
    setTimeout(
      () => reject(new Error('Email send timed out. Please try again.')),
      MAIL_SEND_TIMEOUT_MS
    );
  });

  await Promise.race([mailTask, timeoutTask]);

  return { delivered: true, provider: 'smtp' };
}

async function sendWeeklyReportEmail({ to, name, reportHtml }) {
  const html = `
    <p>Hi ${name || 'there'},</p>
    <p>Here is your Moodiary weekly report.</p>
    ${reportHtml}
  `;

  const resendConfig = getResendConfig();
  if (resendConfig) {
    if (typeof fetch !== 'function') {
      throw new Error('Fetch API is unavailable in current Node runtime');
    }
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), MAIL_SEND_TIMEOUT_MS);
    try {
      const response = await fetch(RESEND_API_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${resendConfig.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: resendConfig.from,
          to: [to],
          subject: 'Your Moodiary weekly report',
          html,
        }),
        signal: controller.signal,
      });
      if (!response.ok) {
        const details = await response.text();
        throw new Error(`Resend API failed (${response.status}): ${details}`);
      }
      return { delivered: true, provider: 'resend' };
    } finally {
      clearTimeout(timeoutId);
    }
  }

  const mailer = getTransporter();
  const config = getMailConfig();
  const from = config?.from || 'Moodiary <no-reply@moodiary.app>';

  await mailer.sendMail({
    from,
    to,
    subject: 'Your Moodiary weekly report',
    html,
  });
  return { delivered: true, provider: 'smtp' };
}

module.exports = {
  sendPasswordResetEmail,
  sendWeeklyReportEmail,
};

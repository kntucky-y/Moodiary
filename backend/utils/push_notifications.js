const admin = require('firebase-admin');
const User = require('../models/User');

let messaging;
let startupWarningPrinted = false;

const stringifyValue = (value) => {
  if (value == null) return '';
  if (typeof value === 'string') return value;
  return String(value);
};

const parseServiceAccount = () => {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) return null;
  try {
    // Allow either plain JSON or base64-encoded JSON to simplify deployments.
    if (raw.trim().startsWith('{')) {
      return JSON.parse(raw);
    }
    const decoded = Buffer.from(raw, 'base64').toString('utf8');
    return JSON.parse(decoded);
  } catch (err) {
    console.error('Invalid FIREBASE_SERVICE_ACCOUNT_JSON:', err.message);
    return null;
  }
};

const initMessaging = () => {
  if (messaging) return messaging;

  const serviceAccount = parseServiceAccount();
  if (!serviceAccount) {
    if (!startupWarningPrinted) {
      startupWarningPrinted = true;
      console.warn('Push notifications disabled: FIREBASE_SERVICE_ACCOUNT_JSON is not configured.');
    }
    return null;
  }

  try {
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
    }
    messaging = admin.messaging();
    return messaging;
  } catch (err) {
    console.error('Failed to initialize Firebase Admin SDK:', err.message);
    return null;
  }
};

const buildPushContent = (payload) => {
  const type = payload.type || 'update';
  if (type === 'friend_message') {
    const sender = payload.from && payload.from.name ? payload.from.name : 'Friend';
    return {
      title: `${sender} sent a message`,
      body: payload.text || 'You have a new message.',
    };
  }

  if (type === 'friend_removed') {
    return {
      title: 'Friendship ended',
      body: payload.message || 'One of your friendships has been removed.',
    };
  }

  return {
    title: payload.title || 'Moodiary update',
    body: payload.message || payload.text || 'You have a new update.',
  };
};

const buildDataPayload = (payload) => {
  const data = {
    type: stringifyValue(payload.type || 'update'),
    friendshipId: stringifyValue(payload.friendshipId),
    messageId: stringifyValue(payload.messageId),
    fromId: stringifyValue(payload.from && payload.from.id),
    fromName: stringifyValue(payload.from && payload.from.name),
    text: stringifyValue(payload.text),
  };

  return Object.fromEntries(
    Object.entries(data).filter(([, value]) => value !== ''),
  );
};

const isUnregisteredTokenError = (errorCode) =>
  errorCode === 'messaging/registration-token-not-registered' ||
  errorCode === 'messaging/invalid-registration-token';

const sendPushNotification = async (targets, payload) => {
  const push = initMessaging();
  if (!push) return;

  const ids = (Array.isArray(targets) ? targets : [targets])
    .map((id) => (id ? id.toString() : ''))
    .filter(Boolean);

  if (!ids.length) return;

  const users = await User.find({ _id: { $in: ids } }, 'pushTokens').lean();
  const tokens = [
    ...new Set(
      users.flatMap((user) =>
        Array.isArray(user.pushTokens)
          ? user.pushTokens.filter((token) => typeof token === 'string' && token.trim())
          : [],
      ),
    ),
  ];

  if (!tokens.length) return;

  const content = buildPushContent(payload);
  const data = buildDataPayload(payload);

  const response = await push.sendEachForMulticast({
    tokens,
    notification: content,
    data,
    android: {
      priority: 'high',
    },
  });

  if (!response.failureCount) return;

  const staleTokens = [];
  response.responses.forEach((result, index) => {
    if (!result.success && isUnregisteredTokenError(result.error && result.error.code)) {
      staleTokens.push(tokens[index]);
    }
  });

  if (!staleTokens.length) return;

  await User.updateMany(
    { pushTokens: { $in: staleTokens } },
    { $pull: { pushTokens: { $in: staleTokens } } },
  );
};

module.exports = {
  sendPushNotification,
};

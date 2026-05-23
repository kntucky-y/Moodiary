const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

const User = require('../models/User');
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const { sendPasswordResetEmail } = require('../utils/email');

const jwtOptions = { expiresIn: '7d' };

const loginLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: 'Too many login attempts. Please try again in 15 minutes.',
  keyGenerator: (req) => `login:${req.ip}`,
});

const registerLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: 'Too many sign-up attempts. Please try again later.',
  keyGenerator: (req) => `register:${req.ip}`,
});

const passwordResetLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: 'Too many password reset requests. Please try again later.',
  keyGenerator: (req) => `password-reset:${req.ip}`,
});

const pushTokenLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: 'Too many push token updates. Please try again later.',
  keyGenerator: (req) => `push-token:${req.userId || req.ip}`,
});

const signToken = (userId) =>
  jwt.sign({ userId }, process.env.JWT_SECRET, jwtOptions);

const sanitizeUser = (user) => ({
  id: user._id,
  name: user.name,
  email: user.email,
  avatarUrl: user.avatarUrl,
  provider: user.provider,
  mbtiLatestType: user.mbtiLatestType || null,
  mbtiLastTestedAt: user.mbtiLastTestedAt || null,
  mbtiAttemptsCount: user.mbtiAttemptsCount || 0,
});

const respondWithAuth = (res, user, status = 200) => {
  const token = signToken(user._id);
  return res.status(status).json({ token, user: sanitizeUser(user) });
};

const hashToken = (token) =>
  crypto.createHash('sha256').update(token).digest('hex');

const generateResetCode = () =>
  crypto.randomInt(100000, 1000000).toString();

const ensurePasswordStrength = (password) =>
  typeof password === 'string' && password.trim().length >= 8;

const normalizePushToken = (token) =>
  typeof token === 'string' ? token.trim() : '';

// POST /api/auth/register
router.post('/register', registerLimiter, async (req, res) => {
  try {
    const { name, email, password } = req.body;

    if (!name || !email || !password) {
      return res.status(400).json({ error: 'All fields are required' });
    }

    if (!ensurePasswordStrength(password)) {
      return res
        .status(400)
        .json({ error: 'Password must be at least 8 characters long' });
    }

    const existing = await User.findOne({ email });
    if (existing) {
      return res.status(409).json({ error: 'Email already in use' });
    }

    const hashed = await bcrypt.hash(password, 12);
    const user = await User.create({
      name,
      email,
      password: hashed,
      provider: 'local',
    });

    respondWithAuth(res, user, 201);
  } catch (err) {
    console.error('Registration error', err);
    res.status(500).json({ error: 'Unable to register at this time' });
  }
});

// POST /api/auth/login
router.post('/login', loginLimiter, async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    if (user.provider !== 'local') {
      return res.status(400).json({
        error: 'This account previously used social login. Please reset your password to continue.',
      });
    }

    const match = await bcrypt.compare(password, user.password);
    if (!match) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    respondWithAuth(res, user);
  } catch (err) {
    console.error('Login error', err);
    res.status(500).json({ error: 'Unable to log in at this time' });
  }
});

// POST /api/auth/forgot-password
router.post('/forgot-password', passwordResetLimiter, async (req, res) => {
  try {
    const { email } = req.body;
    const normalizedEmail = typeof email === 'string' ? email.toLowerCase().trim() : '';
    if (!normalizedEmail) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const user = await User.findOne({ email: normalizedEmail });
    if (!user) {
      return res.json({
        message: 'If that email exists, a reset code has been sent',
      });
    }

    const resetCode = generateResetCode();
    user.resetToken = hashToken(resetCode);
    user.resetTokenExpires = new Date(Date.now() + 10 * 60 * 1000);
    await user.save();

    await sendPasswordResetEmail({
      to: user.email,
      name: user.name,
      code: resetCode,
    });

    res.json({
      message: 'If that email exists, a reset code has been sent',
    });
  } catch (err) {
    console.error('Forgot password error', err);
    const message = String(err?.message || '');
    if (
      /EAUTH|Invalid login|Username and Password not accepted|535|authentication failed/i.test(
        message
      )
    ) {
      return res.status(502).json({
        error:
          'Email sender authentication failed. Verify MAIL_USER and MAIL_PASS (Gmail app password).',
      });
    }

    if (/timed out|timeout/i.test(message)) {
      return res.status(504).json({
        error: 'Email service timed out. Please try again in a moment.',
      });
    }

    res.status(500).json({ error: 'Unable to process request' });
  }
});

// POST /api/auth/reset-password
router.post('/reset-password', passwordResetLimiter, async (req, res) => {
  try {
    const { email, code, token, password } = req.body;

    if (!password) {
      return res.status(400).json({ error: 'New password is required' });
    }

    if (!ensurePasswordStrength(password)) {
      return res
        .status(400)
        .json({ error: 'Password must be at least 8 characters long' });
    }

    const submittedCode = (code || token || '').toString().trim();
    if (!submittedCode) {
      return res.status(400).json({ error: 'Reset code is required' });
    }

    const query = {
      resetToken: hashToken(submittedCode),
      resetTokenExpires: { $gt: new Date() },
    };

    if (typeof email === 'string' && email.trim()) {
      query.email = email.toLowerCase().trim();
    }

    const user = await User.findOne(query);

    if (!user) {
      return res.status(400).json({ error: 'Reset code is invalid or expired' });
    }

    user.password = await bcrypt.hash(password, 12);
    user.resetToken = undefined;
    user.resetTokenExpires = undefined;
    user.provider = 'local';
    await user.save();

    respondWithAuth(res, user);
  } catch (err) {
    console.error('Reset password error', err);
    res.status(500).json({ error: 'Unable to reset password' });
  }
});

// POST /api/auth/push-token
router.post('/push-token', auth, pushTokenLimiter, async (req, res) => {
  try {
    const token = normalizePushToken(req.body.token);
    if (!token) {
      return res.status(400).json({ error: 'Push token is required' });
    }

    await User.updateMany({}, { $pull: { pushTokens: token } });

    await User.findByIdAndUpdate(req.userId, {
      $addToSet: { pushTokens: token },
    });

    res.json({ status: 'registered' });
  } catch (err) {
    console.error('Push token registration error', err);
    res.status(500).json({ error: 'Unable to register push token' });
  }
});

// DELETE /api/auth/push-token
router.delete('/push-token', auth, pushTokenLimiter, async (req, res) => {
  try {
    const token = normalizePushToken(req.body.token);
    if (!token) {
      return res.status(400).json({ error: 'Push token is required' });
    }

    await User.findByIdAndUpdate(req.userId, {
      $pull: { pushTokens: token },
    });

    res.json({ status: 'removed' });
  } catch (err) {
    console.error('Push token removal error', err);
    res.status(500).json({ error: 'Unable to remove push token' });
  }
});

module.exports = router;

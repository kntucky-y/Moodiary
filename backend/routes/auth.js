const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

const User = require('../models/User');
const auth = require('../middleware/auth');
const { sendPasswordResetEmail } = require('../utils/email');

const jwtOptions = { expiresIn: '7d' };

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

const ensurePasswordStrength = (password) =>
  typeof password === 'string' && password.trim().length >= 8;

const normalizePushToken = (token) =>
  typeof token === 'string' ? token.trim() : '';

// POST /api/auth/register
router.post('/register', async (req, res) => {
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
router.post('/login', async (req, res) => {
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
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.json({
        message: 'If that email exists, a reset link has been sent',
      });
    }

    const rawToken = crypto.randomBytes(32).toString('hex');
    user.resetToken = hashToken(rawToken);
    user.resetTokenExpires = new Date(Date.now() + 60 * 60 * 1000);
    await user.save();

    await sendPasswordResetEmail({
      to: user.email,
      name: user.name,
      token: rawToken,
    });

    res.json({
      message: 'If that email exists, a reset link has been sent',
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
router.post('/reset-password', async (req, res) => {
  try {
    const { token, password } = req.body;

    if (!token || !password) {
      return res
        .status(400)
        .json({ error: 'Token and new password are required' });
    }

    if (!ensurePasswordStrength(password)) {
      return res
        .status(400)
        .json({ error: 'Password must be at least 8 characters long' });
    }

    const user = await User.findOne({
      resetToken: hashToken(token),
      resetTokenExpires: { $gt: new Date() },
    });

    if (!user) {
      return res.status(400).json({ error: 'Reset token is invalid or expired' });
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
router.post('/push-token', auth, async (req, res) => {
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
router.delete('/push-token', auth, async (req, res) => {
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

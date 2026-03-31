const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const axios = require('axios');
const { OAuth2Client } = require('google-auth-library');

const User = require('../models/User');
const { sendPasswordResetEmail } = require('../utils/email');

const jwtOptions = { expiresIn: '7d' };

const parseAudiences = (value) =>
  (value || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);

const googleAudiences = parseAudiences(process.env.GOOGLE_CLIENT_ID);
const googleClient = googleAudiences.length ? new OAuth2Client() : null;

const signToken = (userId) =>
  jwt.sign({ userId }, process.env.JWT_SECRET, jwtOptions);

const sanitizeUser = (user) => ({
  id: user._id,
  name: user.name,
  email: user.email,
  avatarUrl: user.avatarUrl,
  provider: user.provider,
});

const respondWithAuth = (res, user, status = 200) => {
  const token = signToken(user._id);
  return res.status(status).json({ token, user: sanitizeUser(user) });
};

const hashToken = (token) =>
  crypto.createHash('sha256').update(token).digest('hex');

const ensurePasswordStrength = (password) =>
  typeof password === 'string' && password.trim().length >= 8;

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
        error: 'Use the social sign-in buttons associated with this account',
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

// POST /api/auth/google
router.post('/google', async (req, res) => {
  try {
    if (!googleClient) {
      return res
        .status(500)
        .json({ error: 'Google OAuth is not configured on the server' });
    }

    const { idToken } = req.body;
    if (!idToken) {
      return res.status(400).json({ error: 'idToken is required' });
    }

    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: googleAudiences,
    });

    const payload = ticket.getPayload();
    const { sub, email, name, picture } = payload;

    if (!email) {
      return res.status(400).json({ error: 'Google account has no email' });
    }

    let user = await User.findOne({
      $or: [{ providerId: sub }, { email }],
    });

    if (!user) {
      user = await User.create({
        name: name || email.split('@')[0],
        email,
        provider: 'google',
        providerId: sub,
        avatarUrl: picture,
      });
    } else {
      user.providerId = user.providerId || sub;
      user.avatarUrl = user.avatarUrl || picture;
      if (!user.password) {
        user.provider = 'google';
      }
      await user.save();
    }

    respondWithAuth(res, user);
  } catch (err) {
    console.error('Google login error', err);
    const message = err?.message || 'Unable to sign in with Google';
    res.status(500).json({ error: message });
  }
});

async function fetchFacebookProfile(accessToken) {
  const appId = process.env.FACEBOOK_APP_ID;
  const appSecret = process.env.FACEBOOK_APP_SECRET;
  const hasAppCredentials = appId && appSecret;

  if (hasAppCredentials) {
    const appAccessToken = `${appId}|${appSecret}`;

    const debug = await axios.get('https://graph.facebook.com/debug_token', {
      params: {
        input_token: accessToken,
        access_token: appAccessToken,
      },
    });

    const debugData = debug.data?.data;
    if (!debugData?.is_valid || debugData.app_id !== appId) {
      throw new Error('Invalid Facebook token');
    }
  } else {
    console.warn(
      'FACEBOOK_APP_ID / FACEBOOK_APP_SECRET missing. Skipping token validation.',
    );
  }

  const profile = await axios.get('https://graph.facebook.com/me', {
    params: {
      fields: 'id,name,email,picture.type(large)',
      access_token: accessToken,
    },
  });

  return profile.data;
}

// POST /api/auth/facebook
router.post('/facebook', async (req, res) => {
  try {
    const { accessToken } = req.body;
    if (!accessToken) {
      return res.status(400).json({ error: 'accessToken is required' });
    }

    const profile = await fetchFacebookProfile(accessToken);
    const email = profile.email;

    if (!email) {
      return res
        .status(400)
        .json({ error: 'Facebook account must share an email address' });
    }

    let user = await User.findOne({
      $or: [{ providerId: profile.id }, { email }],
    });

    if (!user) {
      user = await User.create({
        name: profile.name || email.split('@')[0],
        email,
        provider: 'facebook',
        providerId: profile.id,
        avatarUrl: profile.picture?.data?.url,
      });
    } else {
      user.providerId = user.providerId || profile.id;
      user.avatarUrl = user.avatarUrl || profile.picture?.data?.url;
      if (!user.password) {
        user.provider = 'facebook';
      }
      await user.save();
    }

    respondWithAuth(res, user);
  } catch (err) {
    console.error('Facebook login error', err);
    const message = err?.message || 'Unable to sign in with Facebook';
    res.status(500).json({ error: message });
  }
});

module.exports = router;

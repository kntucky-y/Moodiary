const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

const User = require('../models/User');
const MoodLog = require('../models/Mood');
const ForumPost = require('../models/ForumPost');
const auth = require('../middleware/auth');

const sanitizeUser = (user) => ({
  id: user._id,
  name: user.name,
  email: user.email,
  avatarUrl: user.avatarUrl,
  bio: user.bio,
  provider: user.provider,
  createdAt: user.createdAt,
});

const MOOD_LABELS = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];
const MOOD_ASSETS = [
  'assets/terrible.png',
  'assets/bad.png',
  'assets/okay.png',
  'assets/good.png',
  'assets/excellent.png',
];

const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const ensureOwnUser = (req, res) => {
  if (req.userId !== req.params.id) {
    res.status(403).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
};

function serializePublicPost(post) {
  return {
    id: String(post._id),
    title: post.title,
    content: post.content,
    isAnonymous: post.isAnonymous,
    createdAt: post.createdAt,
    companionId: post.companionId || 1,
  };
}

// GET /api/users/profile/:id - Get user profile
router.get('/profile/:id', async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }

    const [user, latestMood, publicPosts] = await Promise.all([
      User.findById(id).select('name email avatarUrl bio createdAt'),
      MoodLog.findOne({ userId: id }).sort({ dateKey: -1, createdAt: -1 }),
      ForumPost.find({ userId: id, isArchived: { $ne: true } })
        .sort({ createdAt: -1 })
        .limit(6),
    ]);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const currentMood = latestMood
      ? {
          level: latestMood.moodLevel,
          label: MOOD_LABELS[(latestMood.moodLevel || 3) - 1] || 'Okay',
          asset:
            MOOD_ASSETS[(latestMood.moodLevel || 3) - 1] || 'assets/okay.png',
          dateKey: latestMood.dateKey,
        }
      : null;

    res.json({
      user: sanitizeUser(user),
      currentMood,
      publicPosts: publicPosts.map(serializePublicPost),
    });
  } catch (err) {
    console.error('Get user error', err);
    res.status(500).json({ error: 'Unable to fetch user profile' });
  }
});

// GET /api/users/search?query=... - Search users
router.get('/search/query', auth, async (req, res) => {
  try {
    const query = (req.query.query || '').toString().trim();
    const limit = Math.min(30, Math.max(1, Number(req.query.limit) || 20));
    const offset = Math.max(0, Number(req.query.offset) || 0);
    const excludeBlocked = String(req.query.excludeBlocked ?? 'true').toLowerCase() !== 'false';

    if (query.length < 2) {
      return res.status(400).json({ error: 'Query must be at least 2 characters' });
    }

    const regex = new RegExp(escapeRegex(query), 'i');
    const currentUser = await User.findById(req.userId, 'blockedUsers mutedUsers').lean();
    const blockedSet = new Set((currentUser?.blockedUsers || []).map((id) => id.toString()));
    const mutedSet = new Set((currentUser?.mutedUsers || []).map((id) => id.toString()));

    const baseFilter = {
      $or: [
        { name: regex },
        { email: regex },
      ],
      _id: { $ne: req.userId },
    };

    const [matches, total] = await Promise.all([
      User.find(baseFilter)
        .select('name email avatarUrl bio createdAt')
        .sort({ createdAt: -1 })
        .skip(offset)
        .limit(limit)
        .lean(),
      User.countDocuments(baseFilter),
    ]);

    const results = matches
      .filter((user) => {
        if (!excludeBlocked) return true;
        const userId = user._id.toString();
        return !blockedSet.has(userId) && !mutedSet.has(userId);
      })
      .map((user) => ({
        id: user._id.toString(),
        name: user.name,
        email: user.email,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
      }));

    res.json({
      results,
      total,
      offset,
      limit,
      hasMore: offset + results.length < total,
    });
  } catch (err) {
    console.error('Search users error', err);
    res.status(500).json({ error: 'Unable to search users' });
  }
});

// PATCH /api/users/:id - Update user profile (authenticated)
router.patch('/:id', auth, async (req, res) => {
  try {
    // Only allow users to update their own profile
    if (req.userId !== req.params.id) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const { name, bio, avatarUrl, email, currentPassword, newPassword } = req.body;

    const user = await User.findById(req.params.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check current password if trying to change email
    if (email && email !== user.email) {
      if (!currentPassword) {
        return res
          .status(400)
          .json({ error: 'Current password required to change email' });
      }

      const match = await bcrypt.compare(currentPassword, user.password);
      if (!match) {
        return res.status(401).json({ error: 'Incorrect current password' });
      }

      // Check if new email is already in use
      const existing = await User.findOne({ email });
      if (existing) {
        return res.status(409).json({ error: 'Email already in use' });
      }

      user.email = email;
    }

    // Update name
    if (name && typeof name === 'string' && name.trim().length > 0) {
      user.name = name.trim();
    }

    // Update bio
    if (bio !== undefined) {
      user.bio = typeof bio === 'string' ? bio.trim().substring(0, 500) : '';
    }

    // Update avatar
    if (avatarUrl && typeof avatarUrl === 'string') {
      user.avatarUrl = avatarUrl.trim();
    }

    // Change password if requested
    if (newPassword) {
      if (!currentPassword) {
        return res
          .status(400)
          .json({ error: 'Current password required to change password' });
      }

      const match = await bcrypt.compare(currentPassword, user.password);
      if (!match) {
        return res.status(401).json({ error: 'Incorrect current password' });
      }

      if (typeof newPassword !== 'string' || newPassword.trim().length < 8) {
        return res
          .status(400)
          .json({ error: 'Password must be at least 8 characters long' });
      }

      user.password = await bcrypt.hash(newPassword, 12);
    }

    await user.save();
    res.json({ user: sanitizeUser(user) });
  } catch (err) {
    console.error('Update profile error', err);
    res.status(500).json({ error: 'Unable to update profile' });
  }
});

// DELETE /api/users/:id - Delete account (authenticated)
router.delete('/:id', auth, async (req, res) => {
  try {
    // Only allow users to delete their own account
    if (req.userId !== req.params.id) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const { password } = req.body;
    if (!password) {
      return res
        .status(400)
        .json({ error: 'Password required to delete account' });
    }

    const user = await User.findById(req.params.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify password
    const match = await bcrypt.compare(password, user.password);
    if (!match) {
      return res.status(401).json({ error: 'Incorrect password' });
    }

    // Delete user
    await User.findByIdAndDelete(req.params.id);

    res.json({ message: 'Account deleted successfully' });
  } catch (err) {
    console.error('Delete account error', err);
    res.status(500).json({ error: 'Unable to delete account' });
  }
});

// POST /api/users/:id/block - Block user
router.post('/:id/block', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const { targetUserId } = req.body;

    if (!targetUserId) {
      return res.status(400).json({ error: 'Target user ID is required' });
    }

    if (req.userId === targetUserId) {
      return res.status(400).json({ error: 'Cannot block yourself' });
    }

    // Validate ObjectId
    if (!mongoose.Types.ObjectId.isValid(targetUserId)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if already blocked
    if (user.blockedUsers.some((id) => id.toString() === targetUserId)) {
      return res.status(400).json({ error: 'User already blocked' });
    }

    user.blockedUsers.push(targetUserId);
    await user.save();

    res.json({ message: 'User blocked successfully' });
  } catch (err) {
    console.error('Block user error', err);
    res.status(500).json({ error: 'Unable to block user' });
  }
});

// POST /api/users/:id/unblock - Unblock user
router.post('/:id/unblock', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const { targetUserId } = req.body;

    if (!targetUserId) {
      return res.status(400).json({ error: 'Target user ID is required' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    user.blockedUsers = user.blockedUsers.filter(
      (id) => id.toString() !== targetUserId
    );
    await user.save();

    res.json({ message: 'User unblocked successfully' });
  } catch (err) {
    console.error('Unblock user error', err);
    res.status(500).json({ error: 'Unable to unblock user' });
  }
});

// GET /api/users/:id/blocked - Get list of blocked users
router.get('/:id/blocked', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const user = await User.findById(req.params.id)
      .populate('blockedUsers', 'name email avatarUrl')
      .select('blockedUsers');

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ blockedUsers: user.blockedUsers });
  } catch (err) {
    console.error('Get blocked users error', err);
    res.status(500).json({ error: 'Unable to fetch blocked users' });
  }
});

// POST /api/users/:id/mute - Mute user (chat + notifications)
router.post('/:id/mute', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const { targetUserId } = req.body;

    if (!targetUserId) {
      return res.status(400).json({ error: 'Target user ID is required' });
    }

    if (req.userId === targetUserId) {
      return res.status(400).json({ error: 'Cannot mute yourself' });
    }

    if (!mongoose.Types.ObjectId.isValid(targetUserId)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (user.mutedUsers.some((id) => id.toString() === targetUserId)) {
      return res.status(400).json({ error: 'User already muted' });
    }

    user.mutedUsers.push(targetUserId);
    await user.save();

    res.json({ message: 'User muted successfully' });
  } catch (err) {
    console.error('Mute user error', err);
    res.status(500).json({ error: 'Unable to mute user' });
  }
});

// POST /api/users/:id/unmute - Unmute user
router.post('/:id/unmute', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const { targetUserId } = req.body;

    if (!targetUserId) {
      return res.status(400).json({ error: 'Target user ID is required' });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    user.mutedUsers = user.mutedUsers.filter(
      (id) => id.toString() !== targetUserId,
    );
    await user.save();

    res.json({ message: 'User unmuted successfully' });
  } catch (err) {
    console.error('Unmute user error', err);
    res.status(500).json({ error: 'Unable to unmute user' });
  }
});

// GET /api/users/:id/muted - Get list of muted users
router.get('/:id/muted', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const user = await User.findById(req.params.id)
      .populate('mutedUsers', 'name email avatarUrl')
      .select('mutedUsers');

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ mutedUsers: user.mutedUsers });
  } catch (err) {
    console.error('Get muted users error', err);
    res.status(500).json({ error: 'Unable to fetch muted users' });
  }
});

module.exports = router;

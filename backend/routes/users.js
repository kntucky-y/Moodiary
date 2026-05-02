const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');

const User = require('../models/User');
const MoodLog = require('../models/Mood');
const ForumPost = require('../models/ForumPost');
const UserReport = require('../models/UserReport');
const MbtiTestAttempt = require('../models/MbtiTestAttempt');
const Friendship = require('../models/Friendship');
const FriendRequest = require('../models/FriendRequest');
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const { scoreMbti } = require('../utils/mbti');
const { getIO, emitNotification } = require('../socket');

const sanitizeUser = (user) => ({
  id: user._id,
  name: user.name,
  email: user.email,
  avatarUrl: user.avatarUrl,
  bio: user.bio,
  provider: user.provider,
  createdAt: user.createdAt,
  mbtiLatestType: user.mbtiLatestType || null,
  mbtiLastTestedAt: user.mbtiLastTestedAt || null,
  mbtiAttemptsCount: user.mbtiAttemptsCount || 0,
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

const parseDateKey = (dateKey) => {
  if (typeof dateKey !== 'string') return null;
  const parts = dateKey.split('-');
  if (parts.length !== 3) return null;
  const y = Number(parts[0]);
  const m = Number(parts[1]);
  const d = Number(parts[2]);
  if (!Number.isInteger(y) || !Number.isInteger(m) || !Number.isInteger(d)) {
    return null;
  }
  return new Date(y, m - 1, d);
};

const toDateKey = (date) => {
  const y = date.getFullYear().toString().padStart(4, '0');
  const m = (date.getMonth() + 1).toString().padStart(2, '0');
  const d = date.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${d}`;
};

const hasProgress = (entry) => {
  if (!entry || typeof entry !== 'object') return false;
  if (typeof entry.moodLevel === 'number' && entry.moodLevel >= 1 && entry.moodLevel <= 5) {
    return true;
  }
  if (typeof entry.taskScore === 'number' && entry.taskScore > 0) {
    return true;
  }
  if (typeof entry.activityScore === 'number' && entry.activityScore > 0) {
    return true;
  }
  if (typeof entry.score === 'number' && entry.score > 0) {
    return true;
  }
  if (Array.isArray(entry.activities) && entry.activities.length > 0) {
    return true;
  }
  return false;
};

const calculateCurrentStreak = (moodLogs) => {
  const dateKeys = new Set();
  for (const entry of moodLogs || []) {
    if (!hasProgress(entry)) continue;
    const dateKey = entry.dateKey;
    if (typeof dateKey === 'string' && dateKey.length > 0) {
      dateKeys.add(dateKey);
    }
  }

  if (dateKeys.size === 0) return 0;

  const sorted = Array.from(dateKeys).sort((a, b) => b.localeCompare(a));
  const latestDate = parseDateKey(sorted[0]);
  if (!latestDate) return 0;

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const latest = new Date(latestDate.getFullYear(), latestDate.getMonth(), latestDate.getDate());
  const msPerDay = 24 * 60 * 60 * 1000;
  const gapFromToday = Math.floor((today.getTime() - latest.getTime()) / msPerDay);
  if (gapFromToday > 1) return 0;

  let streak = 1;
  let cursor = latest;
  while (true) {
    const prev = new Date(cursor);
    prev.setDate(prev.getDate() - 1);
    const prevKey = toDateKey(prev);
    if (dateKeys.has(prevKey)) {
      streak += 1;
      cursor = prev;
    } else {
      break;
    }
  }
  return streak;
};

const ensureOwnUser = (req, res) => {
  if (req.userId !== req.params.id) {
    res.status(403).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
};

const mbtiSubmitLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 3,
  message: 'Too many MBTI submissions. Please try again in an hour.',
  keyGenerator: (req) => `mbti:${req.userId || req.ip}`,
});

const profileUpdateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: 'Too many profile updates. Please wait a moment and try again.',
  keyGenerator: (req) => `profile:${req.userId || req.ip}`,
});

const userActionLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: 'Too many account actions. Please slow down and try again.',
  keyGenerator: (req) => `user-action:${req.userId || req.ip}`,
});

const reportLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 5,
  message: 'Too many reports. Please try again later.',
  keyGenerator: (req) => `report:${req.userId || req.ip}`,
});

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

function serializePartner(friendship, userId) {
  if (!friendship) return null;
  const partner = (friendship.members || []).find(
    (member) => member && member._id.toString() !== userId.toString(),
  );
  if (!partner?._id) return null;
  return {
    id: partner._id.toString(),
    name: partner.name || 'Partner',
    email: partner.email || '',
    avatarUrl: partner.avatarUrl || '',
  };
}

// GET /api/users/profile/:id - Get user profile
router.get('/profile/:id', async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }

    const [user, latestMood, publicPosts, moodLogs, partnerFriendship] = await Promise.all([
      User.findById(id).select(
        'name email avatarUrl bio createdAt mbtiLatestType mbtiLastTestedAt mbtiAttemptsCount',
      ),
      MoodLog.findOne({ userId: id }).sort({ dateKey: -1, createdAt: -1 }),
      ForumPost.find({
        userId: id,
        isArchived: { $ne: true },
        isAnonymous: { $ne: true },
      })
        .sort({ createdAt: -1 })
        .limit(6),
      MoodLog.find({ userId: id })
        .select('dateKey moodLevel taskScore activityScore score activities')
        .lean(),
      Friendship.findOne({
        members: id,
        relationshipRole: 'partner',
        $or: [{ status: 'active' }, { status: { $exists: false } }],
      })
        .populate('members', 'name email avatarUrl')
        .lean(),
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

    const currentStreak = calculateCurrentStreak(moodLogs);

    res.json({
      user: sanitizeUser(user),
      currentMood,
      currentStreak,
      partner: serializePartner(partnerFriendship, id),
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

// GET /api/users/search/suggested - Suggested user accounts
router.get('/search/suggested', auth, async (req, res) => {
  try {
    const limit = Math.min(20, Math.max(1, Number(req.query.limit) || 10));
    const selfUserId = req.userId.toString();
    const [currentUser, friendships, pendingRequests] = await Promise.all([
      User.findById(req.userId, 'blockedUsers mutedUsers').lean(),
      Friendship.find({
        members: req.userId,
        $or: [{ status: 'active' }, { status: { $exists: false } }],
      })
        .select('members')
        .lean(),
      FriendRequest.find({
        status: 'pending',
        $or: [{ requester: req.userId }, { recipient: req.userId }],
      })
        .select('requester recipient')
        .lean(),
    ]);

    const blockedSet = new Set((currentUser?.blockedUsers || []).map((id) => id.toString()));
    const mutedSet = new Set((currentUser?.mutedUsers || []).map((id) => id.toString()));
    const connectedSet = new Set();

    for (const friendship of friendships) {
      for (const memberId of friendship.members || []) {
        const member = memberId?.toString();
        if (member && member !== selfUserId) {
          connectedSet.add(member);
        }
      }
    }

    for (const request of pendingRequests) {
      const requester = request.requester?.toString();
      const recipient = request.recipient?.toString();
      const otherUserId = requester === selfUserId ? recipient : requester;
      if (otherUserId) {
        connectedSet.add(otherUserId);
      }
    }

    const excludedIds = [
      req.userId,
      ...Array.from(connectedSet),
    ];

    const candidates = await User.find({ _id: { $nin: excludedIds } })
      .select('name email avatarUrl bio createdAt')
      .sort({ createdAt: -1 })
      .limit(limit * 3)
      .lean();

    const results = candidates
      .filter((user) => {
        const userId = user._id.toString();
        return (
          !blockedSet.has(userId) &&
          !mutedSet.has(userId) &&
          !connectedSet.has(userId)
        );
      })
      .slice(0, limit)
      .map((user) => ({
        id: user._id.toString(),
        name: user.name,
        email: user.email,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
      }));

    res.json({ results });
  } catch (err) {
    console.error('Suggested users error', err);
    res.status(500).json({ error: 'Unable to load suggested users' });
  }
});

// POST /api/users/:id/report - Report a user for moderation review
router.post('/:id/report', auth, reportLimiter, async (req, res) => {
  try {
    const { reason, details } = req.body;
    const targetUserId = req.params.id;

    if (!mongoose.Types.ObjectId.isValid(targetUserId)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }

    if (!reason || typeof reason !== 'string' || !reason.trim()) {
      return res.status(400).json({ error: 'Reason is required' });
    }

    if (req.userId === targetUserId) {
      return res.status(400).json({ error: 'Cannot report yourself' });
    }

    const targetUser = await User.findById(targetUserId).select('_id');
    if (!targetUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    await UserReport.create({
      reporterId: req.userId,
      targetUserId,
      reason: reason.trim().substring(0, 100),
      details: typeof details === 'string' ? details.trim().substring(0, 1000) : '',
    });

    res.json({ message: 'Report submitted successfully' });
  } catch (err) {
    console.error('Report user error', err);
    res.status(500).json({ error: 'Unable to submit report' });
  }
});

// POST /api/users/:id/mbti/submit - Submit MBTI answers and compute result
router.post('/:id/mbti/submit', auth, mbtiSubmitLimiter, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const { answers } = req.body;
    const result = scoreMbti(answers);
    if (result.error) {
      return res.status(400).json({ error: result.error });
    }

    const user = await User.findById(req.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    await MbtiTestAttempt.create({
      userId: req.userId,
      mbtiType: result.type,
      answers,
      scores: result.scores,
    });

    user.mbtiLatestType = result.type;
    user.mbtiLatestScores = result.scores;
    user.mbtiLastTestedAt = new Date();
    user.mbtiAttemptsCount = (user.mbtiAttemptsCount || 0) + 1;
    await user.save();

    res.json({
      result: {
        type: result.type,
        scores: result.scores,
        suggestedCompanionIds: result.suggestedCompanionIds,
        suggestedCompanions: result.suggestedCompanions,
      },
      attemptsCount: user.mbtiAttemptsCount,
      testedAt: user.mbtiLastTestedAt,
    });
  } catch (err) {
    console.error('Submit MBTI error', err);
    res.status(500).json({ error: 'Unable to submit MBTI test' });
  }
});

// GET /api/users/:id/mbti/history - Get MBTI test history
router.get('/:id/mbti/history', auth, async (req, res) => {
  try {
    if (!ensureOwnUser(req, res)) {
      return;
    }

    const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 10));
    const offset = Math.max(0, Number(req.query.offset) || 0);

    const [items, total] = await Promise.all([
      MbtiTestAttempt.find({ userId: req.userId })
        .sort({ createdAt: -1 })
        .skip(offset)
        .limit(limit)
        .select('mbtiType scores createdAt')
        .lean(),
      MbtiTestAttempt.countDocuments({ userId: req.userId }),
    ]);

    res.json({
      items: items.map((entry) => ({
        id: entry._id.toString(),
        mbtiType: entry.mbtiType,
        scores: entry.scores,
        createdAt: entry.createdAt,
      })),
      total,
      limit,
      offset,
      hasMore: offset + items.length < total,
    });
  } catch (err) {
    console.error('MBTI history error', err);
    res.status(500).json({ error: 'Unable to fetch MBTI history' });
  }
});

// PATCH /api/users/:id - Update user profile (authenticated)
router.patch('/:id', auth, profileUpdateLimiter, async (req, res) => {
  try {
    // Only allow users to update their own profile
    if (req.userId !== req.params.id) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const {
      name,
      bio,
      avatarUrl,
      email,
      currentPassword,
      newPassword,
      mbtiLatestType,
    } = req.body;

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

    // Optional manual MBTI type override from trusted client flows.
    if (mbtiLatestType !== undefined && mbtiLatestType !== null) {
      const allowedTypes = new Set([
        'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
        'ISTP', 'ISFP', 'INFP', 'INTP',
        'ESTP', 'ESFP', 'ENFP', 'ENTP',
        'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ',
      ]);
      if (!allowedTypes.has(mbtiLatestType)) {
        return res.status(400).json({ error: 'Invalid MBTI type' });
      }
      user.mbtiLatestType = mbtiLatestType;
      user.mbtiLastTestedAt = new Date();
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
router.delete('/:id', auth, profileUpdateLimiter, async (req, res) => {
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
router.post('/:id/block', auth, userActionLimiter, async (req, res) => {
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

    const friendship = await Friendship.findOne({
      members: { $all: [req.userId, targetUserId] },
      $or: [{ status: 'active' }, { status: { $exists: false } }],
    });
    if (friendship) {
      friendship.status = 'archived';
      friendship.endedAt = new Date();
      await friendship.save();

      try {
        getIO().to(`friendship:${friendship._id}`).emit('friends:removed', {
          friendshipId: friendship._id.toString(),
        });
      } catch (_) {
        // Socket layer not initialized; skip emit.
      }

      emitNotification([req.userId, targetUserId], {
        type: 'friend_removed',
        friendshipId: friendship._id.toString(),
        targetUserId,
        message: 'Friendship ended',
        at: new Date().toISOString(),
      });
    }

    await FriendRequest.deleteMany({
      $or: [
        { requester: req.userId, recipient: targetUserId },
        { requester: targetUserId, recipient: req.userId },
      ],
      status: 'pending',
    });

    await user.save();

    res.json({ message: 'User blocked successfully' });
  } catch (err) {
    console.error('Block user error', err);
    res.status(500).json({ error: 'Unable to block user' });
  }
});

// POST /api/users/:id/unblock - Unblock user
router.post('/:id/unblock', auth, userActionLimiter, async (req, res) => {
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
router.post('/:id/mute', auth, userActionLimiter, async (req, res) => {
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

    const activeFriendship = await Friendship.findOne({
      members: { $all: [req.userId, targetUserId] },
      $or: [{ status: 'active' }, { status: { $exists: false } }],
    }).select('_id');

    if (!activeFriendship) {
      return res
        .status(400)
        .json({ error: 'You can only mute users you are friends with' });
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
router.post('/:id/unmute', auth, userActionLimiter, async (req, res) => {
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

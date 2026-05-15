const express = require('express');
const mongoose = require('mongoose');
const router = express.Router();
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const ForumPost = require('../models/ForumPost');
const User = require('../models/User');

const DEFAULT_COMMENT_ASSET = 'assets/okay.png';

const forumWriteLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 60,
  message: 'Too many forum actions. Please slow down and try again.',
  keyGenerator: (req) => `forum:${req.userId || req.ip}`,
});

function toObjectId(id) {
  return new mongoose.Types.ObjectId(id);
}

function sameObjectId(a, b) {
  return String(a) === String(b);
}

function canExposeIdentity({ userId, isAnonymous, currentUserId, publicUserIds }) {
  if (isAnonymous) return false;
  if (sameObjectId(userId, currentUserId)) return true;
  return publicUserIds.has(String(userId));
}

function serializePost(post, currentUserId, publicUserIds) {
  const likedByMe = post.likedBy.some((id) => sameObjectId(id, currentUserId));
  const isMine = sameObjectId(post.userId, currentUserId);
  const postIdentityVisible = canExposeIdentity({
    userId: post.userId,
    isAnonymous: post.isAnonymous,
    currentUserId,
    publicUserIds,
  });
  return {
    id: String(post._id),
    title: post.title,
    content: post.content,
    isAnonymous: post.isAnonymous,
    authorId: postIdentityVisible ? String(post.userId) : null,
    authorName: post.isAnonymous ? 'Anonymous' : post.authorName,
    authorAvatarUrl:
      postIdentityVisible && post.authorAvatarUrl ? post.authorAvatarUrl : null,
    companionId: post.companionId || 1,
    likes: post.likedBy.length,
    isMine,
    likedByMe,
    createdAt: post.createdAt,
    comments: post.comments.map((comment) => ({
      id: String(comment._id),
      text: comment.text,
      moodAsset: comment.moodAsset || DEFAULT_COMMENT_ASSET,
      isAnonymous: comment.isAnonymous,
      authorId: canExposeIdentity({
        userId: comment.userId,
        isAnonymous: comment.isAnonymous,
        currentUserId,
        publicUserIds,
      })
        ? String(comment.userId)
        : null,
      authorName: comment.isAnonymous ? 'Anonymous' : comment.authorName,
      authorAvatarUrl:
        canExposeIdentity({
          userId: comment.userId,
          isAnonymous: comment.isAnonymous,
          currentUserId,
          publicUserIds,
        }) && comment.authorAvatarUrl
          ? comment.authorAvatarUrl
          : null,
      createdAt: comment.createdAt,
    })),
  };
}

async function buildPublicUserIdSet(posts) {
  const authorIds = new Set();
  for (const post of posts) {
    if (post?.userId) authorIds.add(String(post.userId));
    for (const comment of post?.comments || []) {
      if (comment?.userId) authorIds.add(String(comment.userId));
    }
  }

  if (authorIds.size === 0) return new Set();

  const users = await User.find({
    _id: { $in: Array.from(authorIds).map((id) => toObjectId(id)) },
    isProfilePublic: true,
  })
    .select('_id')
    .lean();
  return new Set(users.map((user) => String(user._id)));
}

// GET /api/forums — forum posts for authenticated users
router.get('/', auth, async (req, res) => {
  try {
    const archived = req.query.archived === 'true';
    const query = archived
      ? { isArchived: true, userId: req.userId }
      : { isArchived: { $ne: true } };
    const posts = await ForumPost.find(query)
      .sort({ createdAt: -1 })
      .limit(200);
    const publicUserIds = await buildPublicUserIdSet(posts);
    res.json(posts.map((post) => serializePost(post, req.userId, publicUserIds)));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums — create a post
router.post('/', auth, forumWriteLimiter, async (req, res) => {
  const { title, content, isAnonymous, companionId } = req.body;
  if (!title || !content) {
    return res.status(400).json({ error: 'title and content are required' });
  }
  try {
    const user = await User.findById(req.userId).select('name avatarUrl');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const post = await ForumPost.create({
      userId: toObjectId(req.userId),
      authorName: user.name,
      authorAvatarUrl: user.avatarUrl || '',
      companionId:
        Number.isInteger(companionId) && companionId > 0 ? companionId : 1,
      title: String(title).trim(),
      content: String(content).trim(),
      isAnonymous: isAnonymous !== false,
      likedBy: [],
      comments: [],
      reports: [],
      isArchived: false,
      archivedAt: null,
    });

    const publicUserIds = await buildPublicUserIdSet([post]);
    res.status(201).json(serializePost(post, req.userId, publicUserIds));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums/:id/like — toggle heart
router.post('/:id/like', auth, forumWriteLimiter, async (req, res) => {
  try {
    const post = await ForumPost.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Post not found' });
    if (post.isArchived) {
      return res.status(400).json({ error: 'Cannot like an archived post' });
    }

    const existingIndex = post.likedBy.findIndex((id) =>
      sameObjectId(id, req.userId)
    );

    if (existingIndex >= 0) {
      post.likedBy.splice(existingIndex, 1);
    } else {
      post.likedBy.push(toObjectId(req.userId));
    }

    await post.save();
    res.json({
      likes: post.likedBy.length,
      likedByMe: existingIndex < 0,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums/:id/comments — add comment
router.post('/:id/comments', auth, forumWriteLimiter, async (req, res) => {
  const { text, moodAsset, isAnonymous } = req.body;
  if (!text || !String(text).trim()) {
    return res.status(400).json({ error: 'text is required' });
  }
  try {
    const post = await ForumPost.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Post not found' });
    if (post.isArchived) {
      return res.status(400).json({ error: 'Cannot comment on an archived post' });
    }

    const user = await User.findById(req.userId).select('name avatarUrl');
    if (!user) return res.status(404).json({ error: 'User not found' });

    post.comments.push({
      userId: toObjectId(req.userId),
      authorName: user.name,
      authorAvatarUrl: user.avatarUrl || '',
      isAnonymous: isAnonymous !== false,
      text: String(text).trim(),
      moodAsset:
        typeof moodAsset === 'string' && moodAsset.startsWith('assets/')
          ? moodAsset
          : DEFAULT_COMMENT_ASSET,
    });

    await post.save();
    const publicUserIds = await buildPublicUserIdSet([post]);
    res.status(201).json(serializePost(post, req.userId, publicUserIds));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums/:id/report — report a post
router.post('/:id/report', auth, forumWriteLimiter, async (req, res) => {
  const { reason, details } = req.body;
  if (!reason || !String(reason).trim()) {
    return res.status(400).json({ error: 'reason is required' });
  }
  try {
    const post = await ForumPost.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Post not found' });
    if (post.isArchived) {
      return res.status(400).json({ error: 'Cannot report an archived post' });
    }

    const existing = post.reports.find((r) => sameObjectId(r.reporterId, req.userId));
    if (existing) {
      existing.reason = String(reason).trim();
      existing.details = String(details || '').trim();
      existing.updatedAt = new Date();
    } else {
      post.reports.push({
        reporterId: toObjectId(req.userId),
        reason: String(reason).trim(),
        details: String(details || '').trim(),
      });
    }

    await post.save();
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/forums/:id — soft delete (archive) own active post
router.delete('/:id', auth, forumWriteLimiter, async (req, res) => {
  try {
    const post = await ForumPost.findOneAndUpdate(
      {
        _id: req.params.id,
        userId: req.userId,
        isArchived: { $ne: true },
      },
      {
        isArchived: true,
        archivedAt: new Date(),
      },
      { returnDocument: 'after' }
    );

    if (!post) return res.status(404).json({ error: 'Post not found' });
    const publicUserIds = await buildPublicUserIdSet([post]);
    res.json({ success: true, post: serializePost(post, req.userId, publicUserIds) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums/:id/recover — restore own archived post (likes/comments kept)
router.post('/:id/recover', auth, forumWriteLimiter, async (req, res) => {
  try {
    const post = await ForumPost.findOneAndUpdate(
      {
        _id: req.params.id,
        userId: req.userId,
        isArchived: true,
      },
      {
        isArchived: false,
        archivedAt: null,
      },
      { returnDocument: 'after' }
    );

    if (!post) return res.status(404).json({ error: 'Post not found' });
    const publicUserIds = await buildPublicUserIdSet([post]);
    res.json({ success: true, post: serializePost(post, req.userId, publicUserIds) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/forums/:id/permanent — hard delete own archived post
router.delete('/:id/permanent', auth, forumWriteLimiter, async (req, res) => {
  try {
    const post = await ForumPost.findOneAndDelete({
      _id: req.params.id,
      userId: req.userId,
      isArchived: true,
    });
    if (!post) return res.status(404).json({ error: 'Post not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

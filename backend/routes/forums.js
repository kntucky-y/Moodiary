const express = require('express');
const mongoose = require('mongoose');
const router = express.Router();
const auth = require('../middleware/auth');
const ForumPost = require('../models/ForumPost');
const User = require('../models/User');

const DEFAULT_COMMENT_ASSET = 'assets/okay.png';

function toObjectId(id) {
  return new mongoose.Types.ObjectId(id);
}

function sameObjectId(a, b) {
  return String(a) === String(b);
}

function serializePost(post, currentUserId) {
  const likedByMe = post.likedBy.some((id) => sameObjectId(id, currentUserId));
  const isMine = sameObjectId(post.userId, currentUserId);
  return {
    id: String(post._id),
    title: post.title,
    content: post.content,
    isAnonymous: post.isAnonymous,
    authorId: post.isAnonymous ? null : String(post.userId),
    authorName: post.isAnonymous ? 'Anonymous' : post.authorName,
    authorAvatarUrl:
      post.isAnonymous || !post.authorAvatarUrl ? null : post.authorAvatarUrl,
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
      authorId: comment.isAnonymous ? null : String(comment.userId),
      authorName: comment.isAnonymous ? 'Anonymous' : comment.authorName,
      authorAvatarUrl:
        comment.isAnonymous || !comment.authorAvatarUrl
          ? null
          : comment.authorAvatarUrl,
      createdAt: comment.createdAt,
    })),
  };
}

// GET /api/forums — forum posts for authenticated users
router.get('/', auth, async (req, res) => {
  try {
    const posts = await ForumPost.find().sort({ createdAt: -1 }).limit(200);
    res.json(posts.map((post) => serializePost(post, req.userId)));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums — create a post
router.post('/', auth, async (req, res) => {
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
    });

    res.status(201).json(serializePost(post, req.userId));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums/:id/like — toggle heart
router.post('/:id/like', auth, async (req, res) => {
  try {
    const post = await ForumPost.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Post not found' });

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
router.post('/:id/comments', auth, async (req, res) => {
  const { text, moodAsset, isAnonymous } = req.body;
  if (!text || !String(text).trim()) {
    return res.status(400).json({ error: 'text is required' });
  }
  try {
    const post = await ForumPost.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Post not found' });

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
    res.status(201).json(serializePost(post, req.userId));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/forums/:id/report — report a post
router.post('/:id/report', auth, async (req, res) => {
  const { reason, details } = req.body;
  if (!reason || !String(reason).trim()) {
    return res.status(400).json({ error: 'reason is required' });
  }
  try {
    const post = await ForumPost.findById(req.params.id);
    if (!post) return res.status(404).json({ error: 'Post not found' });

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

module.exports = router;
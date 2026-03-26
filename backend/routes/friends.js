const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const auth = require('../middleware/auth');
const User = require('../models/User');
const Friendship = require('../models/Friendship');
const FriendMessage = require('../models/FriendMessage');

const asObjectId = (id) => new mongoose.Types.ObjectId(id);
const roomFor = (id) => `friendship:${id}`;

const sanitizeUser = (user) => ({
  id: user._id,
  name: user.name,
  email: user.email,
});

const buildFriendPayload = (doc, viewerId) => {
  const friend =
    doc.participants.find(
      (participant) => participant._id.toString() !== viewerId
    ) || doc.participants[0];

  return {
    id: doc._id,
    friend: sanitizeUser(friend),
    status: doc.status,
    lastMessage: doc.lastMessage
      ? {
          text: doc.lastMessage.text,
          sender: doc.lastMessage.sender,
          createdAt: doc.lastMessage.createdAt,
        }
      : null,
  };
};

const ensureMembership = async (friendshipId, userId, { requireAccepted } = {}) => {
  const filter = { _id: friendshipId, participants: userId };
  if (requireAccepted) filter.status = 'accepted';
  const friendship = await Friendship.findOne(filter);
  return friendship;
};

const formatMessage = (message) => ({
  id: message._id,
  friendshipId: message.friendshipId,
  sender: message.sender,
  text: message.text,
  createdAt: message.createdAt,
});

router.post('/request', auth, async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const target = await User.findOne({ email: email.toLowerCase() });
    if (!target) {
      return res.status(404).json({ error: 'User not found' });
    }
    if (target._id.toString() === req.userId) {
      return res.status(400).json({ error: 'You cannot add yourself.' });
    }

    const pairKey = [req.userId, target._id.toString()].sort().join(':');
    const existing = await Friendship.findOne({ participantsKey: pairKey });
    if (existing) {
      if (existing.status === 'pending') {
        return res
          .status(409)
          .json({ error: 'Friend request already pending.' });
      }
      if (existing.status === 'accepted') {
        return res.status(409).json({ error: 'You are already friends.' });
      }
    }

    const friendship = await Friendship.create({
      participants: [req.userId, target._id],
      initiator: req.userId,
    });

    res.status(201).json({
      id: friendship._id,
      status: friendship.status,
      friend: sanitizeUser(target),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/accept', auth, async (req, res) => {
  try {
    const friendship = await Friendship.findById(req.params.id).populate(
      'participants',
      'name email'
    );
    if (!friendship) {
      return res.status(404).json({ error: 'Friend request not found.' });
    }
    if (friendship.status !== 'pending') {
      return res.status(400).json({ error: 'Request already resolved.' });
    }
    if (friendship.initiator.toString() === req.userId) {
      return res.status(400).json({ error: 'You cannot accept your own request.' });
    }
    if (!friendship.participants.some((p) => p._id.toString() === req.userId)) {
      return res.status(403).json({ error: 'Not authorized.' });
    }

    friendship.status = 'accepted';
    await friendship.save();

    const io = req.app.get('io');
    if (io) {
      io.to(roomFor(friendship._id)).emit('friends:status', {
        friendshipId: friendship._id,
        status: 'accepted',
      });
    }

    res.json(buildFriendPayload(friendship, req.userId));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/reject', auth, async (req, res) => {
  try {
    const friendship = await Friendship.findById(req.params.id);
    if (!friendship) {
      return res.status(404).json({ error: 'Friend request not found.' });
    }
    if (!friendship.participants.some((p) => p.toString() === req.userId)) {
      return res.status(403).json({ error: 'Not authorized.' });
    }

    await friendship.deleteOne();
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/', auth, async (req, res) => {
  try {
    const userId = req.userId;
    const friends = await Friendship.find({
      participants: userId,
      status: 'accepted',
    })
      .sort({ 'lastMessage.createdAt': -1, updatedAt: -1 })
      .populate('participants', 'name email');

    const pendingIncoming = await Friendship.find({
      participants: userId,
      status: 'pending',
      initiator: { $ne: userId },
    }).populate('participants', 'name email');

    const pendingOutgoing = await Friendship.find({
      initiator: userId,
      status: 'pending',
    }).populate('participants', 'name email');

    res.json({
      friends: friends.map((doc) => buildFriendPayload(doc, userId)),
      pending: {
        incoming: pendingIncoming.map((doc) => buildFriendPayload(doc, userId)),
        outgoing: pendingOutgoing.map((doc) => buildFriendPayload(doc, userId)),
      },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/:id/messages', auth, async (req, res) => {
  try {
    const friendship = await ensureMembership(req.params.id, req.userId, {
      requireAccepted: true,
    });
    if (!friendship) {
      return res.status(404).json({ error: 'Conversation not found.' });
    }

    const { before } = req.query;
    const filter = { friendshipId: friendship._id };
    if (before) {
      filter.createdAt = { $lt: new Date(before) };
    }

    const messages = await FriendMessage.find(filter)
      .sort({ createdAt: -1 })
      .limit(50);

    const ordered = messages.reverse();
    res.json(ordered.map(formatMessage));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/messages', auth, async (req, res) => {
  try {
    const { text } = req.body;
    if (!text || !text.trim()) {
      return res.status(400).json({ error: 'Message text is required.' });
    }

    const friendship = await ensureMembership(req.params.id, req.userId, {
      requireAccepted: true,
    });
    if (!friendship) {
      return res.status(404).json({ error: 'Conversation not found.' });
    }

    const message = await FriendMessage.create({
      friendshipId: friendship._id,
      sender: req.userId,
      text: text.trim(),
    });

    friendship.lastMessage = {
      text: message.text,
      sender: asObjectId(req.userId),
      createdAt: message.createdAt,
    };
    await friendship.save();

    const payload = formatMessage(message);
    const io = req.app.get('io');
    if (io) {
      io.to(roomFor(friendship._id)).emit('friends:message', payload);
    }

    res.status(201).json(payload);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

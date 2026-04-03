const express = require('express');
const mongoose = require('mongoose');
const auth = require('../middleware/auth');
const User = require('../models/User');
const FriendRequest = require('../models/FriendRequest');
const Friendship = require('../models/Friendship');
const FriendMessage = require('../models/FriendMessage');
const MoodLog = require('../models/Mood');
const {
  buildPairKey,
  ensureFriendshipAccess,
  isValidObjectId,
} = require('../utils/friendships');
const { getIO, emitNotification } = require('../socket');

const router = express.Router();

let legacyStatusFixPromise;
const ensureLegacyFriendshipsActive = () => {
  if (!legacyStatusFixPromise) {
    legacyStatusFixPromise = Friendship.updateMany(
      { status: { $exists: false } },
      { $set: { status: 'active' } },
    ).catch((err) => {
      console.warn('Failed to backfill friendship statuses', err.message);
    });
  }
  return legacyStatusFixPromise;
};

const activeFriendshipFilter = {
  $or: [{ status: 'active' }, { status: { $exists: false } }],
};

const MOOD_LABELS = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];
const MOOD_ASSETS = [
  'assets/terrible.png',
  'assets/bad.png',
  'assets/okay.png',
  'assets/good.png',
  'assets/excellent.png',
];

const formatCurrentMood = (log) => {
  if (!log) return null;
  const level = Math.max(1, Math.min(5, Number(log.moodLevel) || 3));
  const index = level - 1;
  return {
    level,
    label: MOOD_LABELS[index],
    asset: MOOD_ASSETS[index],
    dateKey: log.dateKey,
  };
};

const formatFriendship = async (doc, viewerId) => {
  const members = doc.members || [];
  const friend = members.find(
    (member) => member && member._id.toString() !== viewerId.toString(),
  );

  const latestMood = friend?._id
    ? await MoodLog.findOne({ userId: friend._id })
        .sort({ dateKey: -1, createdAt: -1 })
        .select('moodLevel dateKey')
        .lean()
    : null;

  return {
    id: doc._id.toString(),
    friend: {
      id: friend?._id?.toString() ?? '',
      name: friend?.name ?? 'Friend',
      email: friend?.email ?? '',
      avatarUrl: friend?.avatarUrl ?? '',
    },
    currentMood: formatCurrentMood(latestMood),
    lastMessage: doc.lastMessage
      ? {
          text: doc.lastMessage.text ?? '',
          createdAt: doc.lastMessage.createdAt,
        }
      : null,
  };
};

const formatRequest = (doc, type) => {
  const counterpart =
    type === 'incoming' ? doc.requester : doc.recipient;
  return {
    id: doc._id.toString(),
    friend: {
      id: counterpart?._id?.toString() ?? '',
      name: counterpart?.name ?? 'Friend',
      email: counterpart?.email ?? '',
      avatarUrl: counterpart?.avatarUrl ?? '',
    },
  };
};

const formatMessage = (doc) => ({
  id: doc._id.toString(),
  text: doc.text,
  sender: doc.sender.toString(),
  createdAt:
    doc.createdAt && typeof doc.createdAt.toISOString === 'function'
      ? doc.createdAt.toISOString()
      : new Date().toISOString(),
});

const upsertFriendship = async (userA, userB) => {
  const pairKey = buildPairKey(userA, userB);
  let friendship = await Friendship.findOne({ pairKey });
  if (!friendship) {
    friendship = await Friendship.create({ members: [userA, userB], pairKey });
  } else if (friendship.status !== 'active') {
    friendship.status = 'active';
    friendship.endedAt = null;
    await friendship.save();
  }
  return friendship;
};

router.get('/', auth, async (req, res) => {
  try {
    const userId = req.userId;
    await ensureLegacyFriendshipsActive();

    const [friendships, incoming, outgoing] = await Promise.all([
      Friendship.find({ members: userId, ...activeFriendshipFilter })
        .populate('members', 'name email avatarUrl')
        .sort({ updatedAt: -1 })
        .lean(),
      FriendRequest.find({ recipient: userId, status: 'pending' })
        .populate('requester', 'name email avatarUrl')
        .lean(),
      FriendRequest.find({ requester: userId, status: 'pending' })
        .populate('recipient', 'name email avatarUrl')
        .lean(),
    ]);

    res.json({
      friends: await Promise.all(
        friendships.map((doc) => formatFriendship(doc, userId)),
      ),
      pending: {
        incoming: incoming.map((doc) => formatRequest(doc, 'incoming')),
        outgoing: outgoing.map((doc) => formatRequest(doc, 'outgoing')),
      },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/request', auth, async (req, res) => {
  const email = (req.body.email || '').toLowerCase().trim();
  if (!email) {
    return res.status(400).json({ error: 'Email is required' });
  }

  try {
    const requesterId = req.userId;
    const recipient = await User.findOne({ email });

    if (!recipient) {
      return res.status(404).json({ error: 'No user found with that email' });
    }
    if (recipient._id.toString() === requesterId) {
      return res.status(400).json({ error: 'You cannot add yourself' });
    }

    const pairKey = buildPairKey(requesterId, recipient._id);
    const existingFriendship = await Friendship.findOne({ pairKey });
    if (existingFriendship && existingFriendship.status === 'active') {
      return res.status(409).json({ error: 'You are already friends' });
    }

    const incoming = await FriendRequest.findOne({
      requester: recipient._id,
      recipient: requesterId,
      status: 'pending',
    });

    if (incoming) {
      incoming.status = 'accepted';
      await incoming.save();
      const friendship = await upsertFriendship(requesterId, recipient._id);
      const populated = await Friendship.findById(friendship._id)
        .populate('members', 'name email avatarUrl')
        .lean();
      return res.status(201).json({
        friendship: await formatFriendship(populated, requesterId),
        autoAccepted: true,
      });
    }

    const existingOutgoing = await FriendRequest.findOne({
      requester: requesterId,
      recipient: recipient._id,
      status: 'pending',
    }).populate('recipient', 'name email avatarUrl');

    if (existingOutgoing) {
      return res.status(200).json({
        request: formatRequest(existingOutgoing.toObject(), 'outgoing'),
      });
    }

    const requestDoc = await FriendRequest.create({
      requester: requesterId,
      recipient: recipient._id,
    });

    await requestDoc.populate('recipient', 'name email avatarUrl');
    res.status(201).json({
      request: formatRequest(requestDoc.toObject(), 'outgoing'),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/accept', auth, async (req, res) => {
  try {
    if (!isValidObjectId(req.params.id)) {
      return res.status(400).json({ error: 'Invalid request id' });
    }
    const request = await FriendRequest.findById(req.params.id);
    if (!request || request.status !== 'pending') {
      return res.status(404).json({ error: 'Request not found' });
    }
    if (request.recipient.toString() !== req.userId.toString()) {
      return res.status(403).json({ error: 'You cannot accept this request' });
    }

    request.status = 'accepted';
    await request.save();

    const friendship = await upsertFriendship(
      request.requester,
      request.recipient,
    );

    await FriendRequest.deleteMany({
      status: 'pending',
      $or: [
        { requester: request.requester, recipient: request.recipient },
        { requester: request.recipient, recipient: request.requester },
      ],
    });

    const populated = await Friendship.findById(friendship._id)
      .populate('members', 'name email avatarUrl')
      .lean();
    res.json({ friend: await formatFriendship(populated, req.userId) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/reject', auth, async (req, res) => {
  try {
    if (!isValidObjectId(req.params.id)) {
      return res.status(400).json({ error: 'Invalid request id' });
    }
    const request = await FriendRequest.findById(req.params.id);
    if (!request) {
      return res.status(404).json({ error: 'Request not found' });
    }

    const isRecipient = request.recipient.toString() === req.userId.toString();
    const isRequester = request.requester.toString() === req.userId.toString();

    if (!isRecipient && !isRequester) {
      return res.status(403).json({ error: 'You cannot update this request' });
    }

    await request.deleteOne();
    res.json({ status: 'removed' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.get('/:id/messages', auth, async (req, res) => {
  try {
    await ensureFriendshipAccess(req.params.id, req.userId);
    const messages = await FriendMessage.find({ friendship: req.params.id })
      .sort({ createdAt: 1 })
      .lean();
    res.json(messages.map(formatMessage));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/messages', auth, async (req, res) => {
  const text = (req.body.text || '').trim();
  if (!text) {
    return res.status(400).json({ error: 'Message text is required' });
  }

  try {
    const friendship = await ensureFriendshipAccess(
      req.params.id,
      req.userId,
    );

    const message = await FriendMessage.create({
      friendship: new mongoose.Types.ObjectId(req.params.id),
      sender: req.userId,
      text,
    });

    await Friendship.findByIdAndUpdate(req.params.id, {
      lastMessage: {
        text,
        sender: req.userId,
        createdAt: message.createdAt,
      },
    });

    const payload = {
      ...formatMessage(message),
      friendshipId: req.params.id,
    };

    try {
      getIO()
        .to(`friendship:${req.params.id}`)
        .emit('friends:message', payload);
    } catch (_) {
      // Socket layer not initialized; skip emit.
    }

    const recipients = friendship.members
      .map((member) => member.toString())
      .filter((memberId) => memberId !== req.userId.toString());
    if (recipients.length) {
      const sender = await User.findById(req.userId, 'name').lean();
      emitNotification(recipients, {
        type: 'friend_message',
        friendshipId: req.params.id,
        messageId: payload.id,
        text,
        from: {
          id: req.userId.toString(),
          name: sender?.name ?? 'Friend',
        },
        createdAt: payload.createdAt,
      });
    }

    res.status(201).json(payload);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.delete('/:id', auth, async (req, res) => {
  try {
    const friendship = await ensureFriendshipAccess(
      req.params.id,
      req.userId,
    );

    friendship.status = 'archived';
    friendship.endedAt = new Date();
    await friendship.save();

    try {
      getIO()
        .to(`friendship:${req.params.id}`)
        .emit('friends:removed', { friendshipId: req.params.id });
    } catch (_) {
      // Socket layer not initialized; skip emit.
    }

    emitNotification(
      friendship.members,
      {
        type: 'friend_removed',
        friendshipId: req.params.id,
        message: 'Friendship ended',
        at: new Date().toISOString(),
      },
    );

    res.json({ status: 'unfriended' });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

module.exports = router;

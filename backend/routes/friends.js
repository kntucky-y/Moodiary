const express = require('express');
const mongoose = require('mongoose');
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const User = require('../models/User');
const FriendRequest = require('../models/FriendRequest');
const Friendship = require('../models/Friendship');
const FriendMessage = require('../models/FriendMessage');
const FriendChatState = require('../models/FriendChatState');
const MoodLog = require('../models/Mood');
const {
  buildPairKey,
  ensureFriendshipAccess,
  isValidObjectId,
} = require('../utils/friendships');
const { getIO, emitNotification } = require('../socket');

const router = express.Router();

const friendRequestLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 10,
  message: 'Too many friend requests. Please try again later.',
  keyGenerator: (req) => `friend-request:${req.userId || req.ip}`,
});

const friendActionLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: 'Too many friend actions. Please slow down and try again.',
  keyGenerator: (req) => `friend-action:${req.userId || req.ip}`,
});

const friendMessageLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 120,
  message: 'Too many friend messages. Please slow down and try again.',
  keyGenerator: (req) => `friend-message:${req.userId || req.ip}`,
});

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
    relationship: relationshipForViewer(doc, viewerId),
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

const formatMessage = (doc) => {
  const isUnsent = !!doc.unsentAt;
  return {
    id: doc._id.toString(),
    text: isUnsent ? '' : doc.text || '',
    unsentAt: doc.unsentAt ? doc.unsentAt.toISOString() : null,
    unsentBy: doc.unsentBy ? doc.unsentBy.toString() : null,
    sender: doc.sender.toString(),
    createdAt:
      doc.createdAt && typeof doc.createdAt.toISOString === 'function'
        ? doc.createdAt.toISOString()
        : new Date().toISOString(),
  };
};

const isMutedBy = (user, targetUserId) =>
  (user?.mutedUsers || []).some((id) => id.toString() === targetUserId.toString());

const canDeliverFromSender = async (senderId, recipientIds) => {
  if (!senderId || !recipientIds?.length) {
    return [];
  }

  const recipients = await User.find(
    { _id: { $in: recipientIds } },
    'blockedUsers mutedUsers',
  ).lean();

  return recipients
    .filter((user) => {
      const blocked = (user.blockedUsers || []).some(
        (id) => id.toString() === senderId.toString(),
      );
      const muted = isMutedBy(user, senderId);
      return !blocked && !muted;
    })
    .map((user) => user._id.toString());
};

const isChatMutedBetween = async (userAId, userBId) => {
  const [userA, userB] = await Promise.all([
    User.findById(userAId, 'mutedUsers').lean(),
    User.findById(userBId, 'mutedUsers').lean(),
  ]);
  return isMutedBy(userA, userBId) || isMutedBy(userB, userAId);
};

const getChatState = async (friendshipId, userId) => {
  const state = await FriendChatState.findOne({
    friendship: friendshipId,
    user: userId,
  }).lean();
  return state?.clearedAt || null;
};

const buildVisibilityFilter = ({ friendshipId, userId, clearedAt }) => {
  const filter = {
    friendship: friendshipId,
    deletedFor: { $ne: new mongoose.Types.ObjectId(userId) },
  };

  if (clearedAt) {
    filter.createdAt = { $gt: clearedAt };
  }

  return filter;
};

const toObjectId = (value) => new mongoose.Types.ObjectId(value);

const relationshipForViewer = (friendship, viewerId) => {
  const role = friendship.relationshipRole === 'partner' ? 'partner' : 'friend';
  if (role === 'partner') {
    return { role, partnerStatus: 'partner' };
  }

  const requestedBy = friendship.partnerRequestBy?.toString();
  if (!requestedBy) {
    return { role, partnerStatus: 'none' };
  }

  return {
    role,
    partnerStatus:
      requestedBy === viewerId.toString() ? 'pendingOutgoing' : 'pendingIncoming',
  };
};

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

    const viewer = await User.findById(userId, 'blockedUsers').lean();
    const viewerBlocked = new Set((viewer?.blockedUsers || []).map((id) => id.toString()));

    const friendIds = friendships
      .map((doc) => {
        const counterpart = (doc.members || []).find(
          (member) => member && member._id.toString() !== userId.toString(),
        );
        return counterpart?._id?.toString() || null;
      })
      .filter(Boolean);

    const counterparts = await User.find(
      { _id: { $in: friendIds } },
      'blockedUsers',
    ).lean();
    const blockedByCounterpart = new Set(
      counterparts
        .filter((u) => (u.blockedUsers || []).some((id) => id.toString() === userId.toString()))
        .map((u) => u._id.toString()),
    );

    const visibleFriendships = friendships.filter((doc) => {
      const counterpart = (doc.members || []).find(
        (member) => member && member._id.toString() !== userId.toString(),
      );
      if (!counterpart?._id) return false;
      const counterpartId = counterpart._id.toString();
      return !viewerBlocked.has(counterpartId) && !blockedByCounterpart.has(counterpartId);
    });

    res.json({
      friends: await Promise.all(
        visibleFriendships.map((doc) => formatFriendship(doc, userId)),
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

router.post('/request', auth, friendRequestLimiter, async (req, res) => {
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

router.post('/:id/accept', auth, friendActionLimiter, async (req, res) => {
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

router.post('/:id/reject', auth, friendActionLimiter, async (req, res) => {
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
    const clearedAt = await getChatState(req.params.id, req.userId);
    const filter = buildVisibilityFilter({
      friendshipId: req.params.id,
      userId: req.userId,
      clearedAt,
    });
    const messages = await FriendMessage.find(filter)
      .sort({ createdAt: 1 })
      .lean();
    res.json(messages.map(formatMessage));
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/messages', auth, friendMessageLimiter, async (req, res) => {
  const text = (req.body.text || '').trim();
  if (!text) {
    return res.status(400).json({ error: 'Message text is required' });
  }

  try {
    const friendship = await ensureFriendshipAccess(
      req.params.id,
      req.userId,
    );

    const recipientIds = friendship.members
      .map((member) => member.toString())
      .filter((memberId) => memberId !== req.userId.toString());

    if (recipientIds.length) {
      const muted = await isChatMutedBetween(req.userId, recipientIds[0]);
      if (muted) {
        return res.status(403).json({
          error: 'Chat is muted between you and this user',
        });
      }
    }

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

    if (recipientIds.length) {
      const recipients = await canDeliverFromSender(req.userId, recipientIds);
      if (!recipients.length) {
        return res.status(201).json(payload);
      }
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

router.delete('/:id/messages/:messageId', auth, async (req, res) => {
  try {
    await ensureFriendshipAccess(req.params.id, req.userId);
    const message = await FriendMessage.findOneAndUpdate(
      {
        _id: req.params.messageId,
        friendship: req.params.id,
      },
      { $addToSet: { deletedFor: new mongoose.Types.ObjectId(req.userId) } },
      { returnDocument: 'after' }
    ).lean();

    if (!message) {
      return res.status(404).json({ error: 'Message not found' });
    }

    res.json({ status: 'deleted_for_me' });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/messages/:messageId/unsend', auth, async (req, res) => {
  try {
    await ensureFriendshipAccess(req.params.id, req.userId);

    const existing = await FriendMessage.findOne({
      _id: req.params.messageId,
      friendship: req.params.id,
    });

    if (!existing) {
      return res.status(404).json({ error: 'Message not found' });
    }

    if (existing.sender.toString() !== req.userId.toString()) {
      return res.status(403).json({ error: 'You can only unsend your messages' });
    }

    if (existing.unsentAt) {
      return res.json({
        status: 'already_unsent',
        message: formatMessage(existing),
      });
    }

    const updated = await FriendMessage.findOneAndUpdate(
      { _id: existing._id },
      {
        $set: {
          text: '',
          unsentAt: new Date(),
          unsentBy: new mongoose.Types.ObjectId(req.userId),
        },
      },
      { returnDocument: 'after' }
    );

    const friendship = await Friendship.findById(req.params.id);
    if (friendship?.lastMessage?.createdAt && updated?.createdAt) {
      const sameTimestamp =
        friendship.lastMessage.createdAt.getTime() ===
        updated.createdAt.getTime();
      const sameSender =
        friendship.lastMessage.sender?.toString() ===
        updated.sender?.toString();
      if (sameTimestamp && sameSender) {
        friendship.lastMessage.text = 'Message unsent';
        await friendship.save();
      }
    }

    const payload = {
      ...formatMessage(updated),
      friendshipId: req.params.id,
    };

    try {
      getIO()
        .to(`friendship:${req.params.id}`)
        .emit('friends:message:update', payload);
    } catch (_) {
      // Socket layer not initialized; skip emit.
    }

    res.json({ status: 'unsent', message: payload });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/messages/clear', auth, async (req, res) => {
  try {
    await ensureFriendshipAccess(req.params.id, req.userId);
    await FriendChatState.findOneAndUpdate(
      { friendship: req.params.id, user: req.userId },
      { clearedAt: new Date() },
      { upsert: true, returnDocument: 'after' }
    );
    res.json({ status: 'cleared' });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.get('/:id/messages/search', auth, async (req, res) => {
  const query = String(req.query.q || '').trim();
  if (!query) {
    return res.status(400).json({ error: 'Query is required' });
  }

  try {
    await ensureFriendshipAccess(req.params.id, req.userId);
    const limitRaw = Number(req.query.limit || 20);
    const limit = Math.min(Math.max(limitRaw, 1), 50);
    const clearedAt = await getChatState(req.params.id, req.userId);
    const filter = buildVisibilityFilter({
      friendshipId: req.params.id,
      userId: req.userId,
      clearedAt,
    });

    const messages = await FriendMessage.find({
      ...filter,
      unsentAt: null,
      $text: { $search: query },
    }, {
      score: { $meta: 'textScore' },
    })
      .sort({ score: { $meta: 'textScore' }, createdAt: -1 })
      .limit(limit)
      .lean();

    res.json({
      query,
      results: messages.map(formatMessage),
    });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.delete('/:id', auth, friendActionLimiter, async (req, res) => {
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

router.post('/:id/partner/request', auth, friendActionLimiter, async (req, res) => {
  try {
    const friendship = await ensureFriendshipAccess(req.params.id, req.userId);
    if (friendship.relationshipRole === 'partner') {
      return res.status(400).json({ error: 'You are already partners' });
    }

    const requestedBy = friendship.partnerRequestBy?.toString();
    if (requestedBy === req.userId.toString()) {
      return res.status(400).json({ error: 'Partner request already sent' });
    }

    if (requestedBy && requestedBy !== req.userId.toString()) {
      return res.status(409).json({
        error: 'There is already an incoming partner request from this friend',
      });
    }

    friendship.relationshipRole = 'friend';
    friendship.partnerRequestBy = toObjectId(req.userId);
    await friendship.save();

    res.json({
      friendshipId: friendship._id.toString(),
      relationship: relationshipForViewer(friendship, req.userId),
      message: 'Partner request sent',
    });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/partner/accept', auth, friendActionLimiter, async (req, res) => {
  try {
    const friendship = await ensureFriendshipAccess(req.params.id, req.userId);
    const requestedBy = friendship.partnerRequestBy?.toString();
    if (!requestedBy) {
      return res.status(404).json({ error: 'No partner request to accept' });
    }
    if (requestedBy === req.userId.toString()) {
      return res.status(400).json({ error: 'You cannot accept your own request' });
    }

    friendship.relationshipRole = 'partner';
    friendship.partnerRequestBy = null;
    await friendship.save();

    res.json({
      friendshipId: friendship._id.toString(),
      relationship: relationshipForViewer(friendship, req.userId),
      message: 'You are now partners',
    });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/partner/decline', auth, friendActionLimiter, async (req, res) => {
  try {
    const friendship = await ensureFriendshipAccess(req.params.id, req.userId);
    const requestedBy = friendship.partnerRequestBy?.toString();
    if (!requestedBy) {
      return res.status(404).json({ error: 'No partner request to decline' });
    }
    if (requestedBy === req.userId.toString()) {
      return res.status(400).json({ error: 'Use cancel request instead' });
    }

    friendship.partnerRequestBy = null;
    friendship.relationshipRole = 'friend';
    await friendship.save();

    res.json({
      friendshipId: friendship._id.toString(),
      relationship: relationshipForViewer(friendship, req.userId),
      message: 'Partner request declined',
    });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

router.post('/:id/partner/remove', auth, friendActionLimiter, async (req, res) => {
  try {
    const friendship = await ensureFriendshipAccess(req.params.id, req.userId);
    friendship.relationshipRole = 'friend';
    friendship.partnerRequestBy = null;
    await friendship.save();

    res.json({
      friendshipId: friendship._id.toString(),
      relationship: relationshipForViewer(friendship, req.userId),
      message: 'Relationship set to friend',
    });
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
});

module.exports = router;

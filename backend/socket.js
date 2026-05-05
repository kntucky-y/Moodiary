const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const FriendMessage = require('./models/FriendMessage');
const Friendship = require('./models/Friendship');
const User = require('./models/User');
const NotificationHistory = require('./models/NotificationHistory');
const { ensureFriendshipAccess } = require('./utils/friendships');
const { sendPushNotification } = require('./utils/push_notifications');

let ioInstance;

const roomName = (id) => `friendship:${id}`;
const userRoom = (id) => `user:${id}`;
const MAX_MESSAGE_LENGTH = 1000;

const isMutedBy = (user, targetUserId) =>
  (user?.mutedUsers || []).some((id) => id.toString() === targetUserId.toString());

const isBlockedBy = (user, targetUserId) =>
  (user?.blockedUsers || []).some((id) => id.toString() === targetUserId.toString());

const isChatMutedBetween = async (userAId, userBId) => {
  const [userA, userB] = await Promise.all([
    User.findById(userAId, 'mutedUsers').lean(),
    User.findById(userBId, 'mutedUsers').lean(),
  ]);
  return isMutedBy(userA, userBId) || isMutedBy(userB, userAId);
};

const filterRecipientsBySender = async (senderId, recipientIds) => {
  if (!senderId || !recipientIds?.length) {
    return [];
  }

  const users = await User.find(
    { _id: { $in: recipientIds } },
    'blockedUsers mutedUsers',
  ).lean();

  return users
    .filter((user) => !isBlockedBy(user, senderId) && !isMutedBy(user, senderId))
    .map((user) => user._id.toString());
};

const formatMessage = (doc, friendshipId) => {
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
    friendshipId,
  };
};

const initSocket = (server) => {
  ioInstance = new Server(server, {
    cors: {
      origin: '*',
      methods: ['GET', 'POST'],
    },
  });

  ioInstance.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) {
      return next(new Error('Unauthorized'));
    }
    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.userId = decoded.userId;
      next();
    } catch (err) {
      next(new Error('Unauthorized'));
    }
  });

  ioInstance.on('connection', (socket) => {
    socket.join(userRoom(socket.userId));

    socket.on('friends:join', async (payload = {}) => {
      const friendshipId = (payload.friendshipId || '').toString().trim();
      if (!friendshipId) return;
      try {
        await ensureFriendshipAccess(friendshipId, socket.userId);
        socket.join(roomName(friendshipId));
        socket.emit('friends:joined', { friendshipId });
      } catch (err) {
        socket.emit('friends:error', {
          friendshipId,
          error: err.message,
        });
      }
    });

    socket.on('friends:leave', (payload = {}) => {
      const friendshipId = (payload.friendshipId || '').toString().trim();
      if (!friendshipId) return;
      socket.leave(roomName(friendshipId));
    });

    socket.on('friends:typing', async (payload = {}) => {
      const friendshipId = (payload.friendshipId || '').toString().trim();
      if (!friendshipId) return;
      const isTyping = !!payload.isTyping;
      try {
        await ensureFriendshipAccess(friendshipId, socket.userId);
        socket.to(roomName(friendshipId)).emit('friends:typing', {
          friendshipId,
          userId: socket.userId.toString(),
          isTyping,
        });
      } catch (err) {
        socket.emit('friends:error', {
          friendshipId,
          error: err.message,
        });
      }
    });

    socket.on('friends:message', async (payload = {}) => {
      const friendshipId = (payload.friendshipId || '').toString().trim();
      const text = (payload.text || '').trim();
      if (!friendshipId || !text) return;
      if (text.length > MAX_MESSAGE_LENGTH) {
        socket.emit('friends:error', {
          friendshipId,
          error: `Message is too long (max ${MAX_MESSAGE_LENGTH} characters)`,
        });
        return;
      }

      try {
        const friendship = await ensureFriendshipAccess(
          friendshipId,
          socket.userId,
        );

        const recipients = friendship.members
          .map((member) => member.toString())
          .filter((memberId) => memberId !== socket.userId.toString());

        if (recipients.length) {
          const muted = await isChatMutedBetween(socket.userId, recipients[0]);
          if (muted) {
            socket.emit('friends:error', {
              friendshipId,
              error: 'Chat is muted between you and this user',
            });
            return;
          }
        }

        const message = await FriendMessage.create({
          friendship: new mongoose.Types.ObjectId(friendshipId),
          sender: socket.userId,
          text,
        });

        await Friendship.findByIdAndUpdate(friendshipId, {
          lastMessage: {
            text,
            sender: socket.userId,
            createdAt: message.createdAt,
          },
        });

        const formatted = formatMessage(message, friendshipId);
        ioInstance.to(roomName(friendshipId)).emit('friends:message', formatted);

        let sender;
        try {
          sender = await User.findById(socket.userId, 'name').lean();
        } catch (_) {
          sender = null;
        }

        const deliverableRecipients = await filterRecipientsBySender(
          socket.userId,
          recipients,
        );
        emitNotification(deliverableRecipients, {
          type: 'friend_message',
          friendshipId,
          messageId: formatted.id,
          text,
          from: {
            id: socket.userId.toString(),
            name: sender?.name ?? 'Friend',
          },
          createdAt: formatted.createdAt,
        });
      } catch (err) {
        socket.emit('friends:error', {
          friendshipId,
          error: err.message,
        });
      }
    });
  });

  return ioInstance;
};

const emitNotification = (targets, payload) => {
  const list = Array.isArray(targets) ? targets : [targets];
  const recipientIds = list
    .map((id) => id && id.toString())
    .filter(Boolean);

  if (recipientIds.length) {
    const documents = recipientIds.map((recipient) => ({
      recipient,
      type: (payload && payload.type) || 'generic',
      payload: payload || {},
    }));
    NotificationHistory.insertMany(documents, { ordered: false }).catch((err) => {
      console.warn('Notification history persistence failed:', err.message);
    });
  }

  if (ioInstance) {
    recipientIds.forEach((userId) => {
      ioInstance.to(userRoom(userId)).emit('notifications:new', payload);
    });
  }

  sendPushNotification(recipientIds, payload).catch((err) => {
    console.warn('Push send failed:', err.message);
  });
};

const getIO = () => {
  if (!ioInstance) {
    throw new Error('Socket.io instance not initialized');
  }
  return ioInstance;
};

module.exports = {
  initSocket,
  getIO,
  emitNotification,
};

const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const FriendMessage = require('./models/FriendMessage');
const Friendship = require('./models/Friendship');
const User = require('./models/User');
const { ensureFriendshipAccess } = require('./utils/friendships');

let ioInstance;

const roomName = (id) => `friendship:${id}`;
const userRoom = (id) => `user:${id}`;

const formatMessage = (doc, friendshipId) => ({
  id: doc._id.toString(),
  text: doc.text,
  sender: doc.sender.toString(),
  createdAt:
    doc.createdAt && typeof doc.createdAt.toISOString === 'function'
      ? doc.createdAt.toISOString()
      : new Date().toISOString(),
  friendshipId,
});

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

    socket.on('friends:message', async (payload = {}) => {
      const friendshipId = (payload.friendshipId || '').toString().trim();
      const text = (payload.text || '').trim();
      if (!friendshipId || !text) return;

      try {
        const friendship = await ensureFriendshipAccess(
          friendshipId,
          socket.userId,
        );

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

        const recipients = friendship.members
          .map((member) => member.toString())
          .filter((memberId) => memberId !== socket.userId.toString());
        let sender;
        try {
          sender = await User.findById(socket.userId, 'name').lean();
        } catch (_) {
          sender = null;
        }

        emitNotification(recipients, {
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
  if (!ioInstance) return;
  const list = Array.isArray(targets) ? targets : [targets];
  list
    .map((id) => id && id.toString())
    .filter(Boolean)
    .forEach((userId) => {
      ioInstance.to(userRoom(userId)).emit('notifications:new', payload);
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

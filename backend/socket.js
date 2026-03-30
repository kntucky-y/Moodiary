const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const FriendMessage = require('./models/FriendMessage');
const Friendship = require('./models/Friendship');
const { ensureFriendshipAccess } = require('./utils/friendships');

let ioInstance;

const roomName = (id) => `friendship:${id}`;

const formatMessage = (doc, friendshipId) => ({
  id: doc._id.toString(),
  text: doc.text,
  sender: doc.sender.toString(),
  createdAt: doc.createdAt,
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
        await ensureFriendshipAccess(friendshipId, socket.userId);

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

const getIO = () => {
  if (!ioInstance) {
    throw new Error('Socket.io instance not initialized');
  }
  return ioInstance;
};

module.exports = {
  initSocket,
  getIO,
};

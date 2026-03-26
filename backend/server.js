const express = require('express');
const http = require('http');
const mongoose = require('mongoose');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const { Server } = require('socket.io');
require('dotenv').config({ path: '.env' });

const moodRoutes = require('./routes/moods');
const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chat');
const journalRoutes = require('./routes/journal');
const forumRoutes = require('./routes/forums');
const friendRoutes = require('./routes/friends');
const Friendship = require('./models/Friendship');
const FriendMessage = require('./models/FriendMessage');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
});

const roomFor = (id) => `friendship:${id}`;

app.set('io', io);
app.use(cors());
app.use(express.json());

app.use('/api/moods', moodRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/journal', journalRoutes);
app.use('/api/forums', forumRoutes);
app.use('/api/friends', friendRoutes);

// Health-check — visit /api/health to confirm env vars are loaded on Railway
app.get('/api/health', (req, res) => {
  const key = process.env.GROQ_API_KEY;
  res.json({
    status: 'ok',
    groqKeyLoaded: !!key,
    groqKeyPrefix: key ? key.slice(0, 8) + '...' : null,
  });
});

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Unauthorized'));
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    socket.userId = payload.userId;
    if (!socket.userId) return next(new Error('Unauthorized'));
    next();
  } catch (err) {
    next(new Error('Unauthorized'));
  }
});

io.on('connection', (socket) => {
  socket.on('friends:join', async ({ friendshipId }) => {
    if (!friendshipId) return;
    const friendship = await Friendship.findOne({
      _id: friendshipId,
      participants: socket.userId,
      status: 'accepted',
    });
    if (!friendship) {
      socket.emit('friends:error', { message: 'Conversation unavailable.' });
      return;
    }
    socket.join(roomFor(friendshipId));
  });

  socket.on('friends:leave', ({ friendshipId }) => {
    if (!friendshipId) return;
    socket.leave(roomFor(friendshipId));
  });

  socket.on('friends:message', async ({ friendshipId, text }) => {
    if (!friendshipId || !text || !text.trim()) return;
    const friendship = await Friendship.findOne({
      _id: friendshipId,
      participants: socket.userId,
      status: 'accepted',
    });
    if (!friendship) {
      socket.emit('friends:error', { message: 'Conversation unavailable.' });
      return;
    }

    const message = await FriendMessage.create({
      friendshipId,
      sender: socket.userId,
      text: text.trim(),
    });

    friendship.lastMessage = {
      text: message.text,
      sender: socket.userId,
      createdAt: message.createdAt,
    };
    await friendship.save();

    const payload = {
      id: message._id,
      friendshipId,
      sender: message.sender,
      text: message.text,
      createdAt: message.createdAt,
    };

    io.to(roomFor(friendshipId)).emit('friends:message', payload);
  });
});

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => {
    console.log('Connected to MongoDB Atlas');
    const port = process.env.PORT || 3000;
    server.listen(port, () => {
      console.log(`Server running on port ${port}`);
    });
  })
  .catch((err) => console.error('MongoDB connection error:', err));

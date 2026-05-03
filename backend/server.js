const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const http = require('http');
require('dotenv').config({ path: '.env' });

const moodRoutes = require('./routes/moods');
const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chat');
const journalRoutes = require('./routes/journal');
const forumRoutes = require('./routes/forums');
const friendRoutes = require('./routes/friends');
const notificationRoutes = require('./routes/notifications');
const userRoutes = require('./routes/users');
const resourceRoutes = require('./routes/resources');
const aiRoutes = require('./routes/ai');

const { initSocket } = require('./socket');

const app = express();
const server = http.createServer(app);
initSocket(server);

app.set('trust proxy', 1);
app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true, limit: '2mb' }));

app.use('/api/moods', moodRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/journal', journalRoutes);
app.use('/api/forums', forumRoutes);
app.use('/api/friends', friendRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/users', userRoutes);
app.use('/api/resources', resourceRoutes);
app.use('/api/ai', aiRoutes);

// Health-check — visit /api/health to confirm env vars are loaded on Railway
app.get('/api/health', (req, res) => {
  const groqKey = process.env.GROQ_API_KEY;
  const geminiKey =
    process.env.GEMINI_API_KEY || process.env.GOOGLE_GENERATIVE_AI_API_KEY;
  res.json({
    status: 'ok',
    groqKeyLoaded: !!groqKey,
    groqKeyPrefix: groqKey ? groqKey.slice(0, 8) + '...' : null,
    geminiKeyLoaded: !!geminiKey,
    geminiModel: process.env.GEMINI_MODEL || 'gemini-1.5-flash',
  });
});

app.use((err, req, res, next) => {
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({ error: 'Request body is too large' });
  }

  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Invalid JSON payload' });
  }

  return next(err);
});

const PORT = process.env.PORT || 5000;

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => {
    console.log('Connected to MongoDB Atlas');
    server.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  })
  .catch((err) => console.error('MongoDB connection error:', err));

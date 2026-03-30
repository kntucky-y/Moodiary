const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config({ path: '.env' });

const moodRoutes = require('./routes/moods');
const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chat');
const journalRoutes = require('./routes/journal');
const forumRoutes = require('./routes/forums');
const friendRoutes = require('./routes/friends');

const app = express();

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

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => {
    console.log('Connected to MongoDB Atlas');
    app.listen(process.env.PORT, () => {
      console.log(`Server running on port ${process.env.PORT}`);
    });
  })
  .catch((err) => console.error('MongoDB connection error:', err));

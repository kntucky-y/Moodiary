const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const moodRoutes = require('./routes/moods');

const app = express();

app.use(cors());
app.use(express.json());

app.use('/api/moods', moodRoutes);

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => {
    console.log('Connected to MongoDB Atlas');
    app.listen(process.env.PORT, () => {
      console.log(`Server running on port ${process.env.PORT}`);
    });
  })
  .catch((err) => console.error('MongoDB connection error:', err));

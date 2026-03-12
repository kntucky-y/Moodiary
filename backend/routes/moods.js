const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const MoodLog = require('../models/Mood');

// GET /api/moods — all logs for the authenticated user
router.get('/', auth, async (req, res) => {
  try {
    const logs = await MoodLog.find({ userId: req.userId }).sort({ dateKey: 1 });
    res.json(logs);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/moods — upsert a mood log for a specific date
router.post('/', auth, async (req, res) => {
  const { dateKey, moodLevel, activities, score } = req.body;

  if (!dateKey || !moodLevel) {
    return res.status(400).json({ error: 'dateKey and moodLevel are required' });
  }

  try {
    const log = await MoodLog.findOneAndUpdate(
      { userId: req.userId, dateKey },
      { moodLevel, activities: activities || [], score: score || 0 },
      { upsert: true, new: true }
    );
    res.json(log);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;


module.exports = router;

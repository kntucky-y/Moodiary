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

// POST /api/moods — partial upsert: calendar sends moodLevel/activities/moodScore,
//                   home sends taskScore; server merges and computes combined score.
router.post('/', auth, async (req, res) => {
  const { dateKey, moodLevel, activities, moodScore, taskScore } = req.body;

  if (!dateKey) {
    return res.status(400).json({ error: 'dateKey is required' });
  }

  try {
    // Read existing record so we can merge without overwriting the other side
    const existing = await MoodLog.findOne({ userId: req.userId, dateKey });

    const newMoodLevel   = moodLevel   !== undefined ? moodLevel   : (existing?.moodLevel   ?? 3);
    const newActivities  = activities  !== undefined ? activities  : (existing?.activities  ?? []);
    const newMoodScore   = moodScore   !== undefined ? moodScore   : (existing?.moodScore   ?? 0);
    const newTaskScore   = taskScore   !== undefined ? taskScore   : (existing?.taskScore   ?? 0);
    const newScore       = newTaskScore + newMoodScore;

    const log = await MoodLog.findOneAndUpdate(
      { userId: req.userId, dateKey },
      { moodLevel: newMoodLevel, activities: newActivities, moodScore: newMoodScore, taskScore: newTaskScore, score: newScore },
      { upsert: true, new: true }
    );
    res.json(log);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;


module.exports = router;

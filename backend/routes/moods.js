const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const MoodLog = require('../models/Mood');

const moodWriteLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: 'Too many mood updates. Please slow down and try again.',
  keyGenerator: (req) => `mood:${req.userId || req.ip}`,
});

// GET /api/moods — all logs for the authenticated user
router.get('/', auth, async (req, res) => {
  try {
    const logs = await MoodLog.find({ userId: req.userId }).sort({ dateKey: 1 });
    res.json(logs);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Points per mood level: index 0 = Terrible … index 4 = Excellent
const MOOD_LEVEL_POINTS = [5, 10, 20, 35, 50];

// POST /api/moods — partial upsert.
//   Home  sends: { dateKey, moodLevel }  or  { dateKey, taskScore }
//   Calendar sends: { dateKey, moodLevel, activities, activityScore }
//   Server always auto-computes moodLevelScore, moodScore, score.
router.post('/', auth, moodWriteLimiter, async (req, res) => {
  const { dateKey, moodLevel, activities, activityScore, taskScore } = req.body;

  if (!dateKey) {
    return res.status(400).json({ error: 'dateKey is required' });
  }

  try {
    const existing = await MoodLog.findOne({ userId: req.userId, dateKey });

    const newMoodLevel      = moodLevel      !== undefined ? moodLevel      : (existing?.moodLevel      ?? 3);
    const newActivities     = activities     !== undefined ? activities     : (existing?.activities     ?? []);
    const newActivityScore  = activityScore  !== undefined ? activityScore  : (existing?.activityScore  ?? 0);
    const newTaskScore      = taskScore      !== undefined ? taskScore      : (existing?.taskScore      ?? 0);
    const newMoodLevelScore = MOOD_LEVEL_POINTS[(newMoodLevel - 1)] ?? 0;
    const newMoodScore      = newMoodLevelScore + newActivityScore;
    const newScore          = newMoodScore + newTaskScore;

    const log = await MoodLog.findOneAndUpdate(
      { userId: req.userId, dateKey },
      { moodLevel: newMoodLevel, activities: newActivities, moodLevelScore: newMoodLevelScore, activityScore: newActivityScore, moodScore: newMoodScore, taskScore: newTaskScore, score: newScore },
      { upsert: true, new: true }
    );
    res.json(log);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;


module.exports = router;

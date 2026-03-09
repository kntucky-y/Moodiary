const express = require('express');
const router = express.Router();
const Mood = require('../models/Mood');

// GET all moods
router.get('/', async (req, res) => {
  try {
    const moods = await Mood.find().sort({ date: -1 });
    res.json(moods);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET a single mood by ID
router.get('/:id', async (req, res) => {
  try {
    const mood = await Mood.findById(req.params.id);
    if (!mood) return res.status(404).json({ error: 'Mood not found' });
    res.json(mood);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST a new mood entry
router.post('/', async (req, res) => {
  try {
    const mood = new Mood({
      mood: req.body.mood,
      note: req.body.note,
      date: req.body.date,
    });
    const saved = await mood.save();
    res.status(201).json(saved);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// DELETE a mood entry
router.delete('/:id', async (req, res) => {
  try {
    const deleted = await Mood.findByIdAndDelete(req.params.id);
    if (!deleted) return res.status(404).json({ error: 'Mood not found' });
    res.json({ message: 'Mood deleted' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const JournalEntry = require('../models/JournalEntry');

// GET /api/journal?archived=true|false — entries for the authenticated user
router.get('/', auth, async (req, res) => {
  try {
    const archived = req.query.archived === 'true';
    const entries = await JournalEntry.find({
      userId: req.userId,
      isArchived: archived ? true : { $ne: true },
    }).sort({ createdAt: -1 });
    res.json(entries);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/journal — create a new entry
router.post('/', auth, async (req, res) => {
  const { title, content, tag } = req.body;
  if (!title || !content) {
    return res.status(400).json({ error: 'title and content are required' });
  }
  try {
    const entry = await JournalEntry.create({
      userId: req.userId,
      title,
      content,
      tag: tag || 'okay',
      isArchived: false,
      archivedAt: null,
    });
    res.status(201).json(entry);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/journal/:id — update an existing entry
router.put('/:id', auth, async (req, res) => {
  const { title, content, tag } = req.body;
  try {
    const entry = await JournalEntry.findOneAndUpdate(
      { _id: req.params.id, userId: req.userId, isArchived: { $ne: true } },
      { title, content, tag },
      { returnDocument: 'after' }
    );
    if (!entry) return res.status(404).json({ error: 'Entry not found' });
    res.json(entry);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/journal/:id — soft delete (archive) an active entry
router.delete('/:id', auth, async (req, res) => {
  try {
    const entry = await JournalEntry.findOneAndUpdate(
      {
        _id: req.params.id,
        userId: req.userId,
        isArchived: { $ne: true },
      },
      {
        isArchived: true,
        archivedAt: new Date(),
      },
      {
        returnDocument: 'after',
      }
    );
    if (!entry) return res.status(404).json({ error: 'Entry not found' });
    res.json({ success: true, entry });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/journal/:id/recover — recover a soft-deleted entry
router.post('/:id/recover', auth, async (req, res) => {
  try {
    const entry = await JournalEntry.findOneAndUpdate({
      _id: req.params.id,
      userId: req.userId,
      isArchived: true,
    }, {
      isArchived: false,
      archivedAt: null,
    }, {
      returnDocument: 'after',
    });
    if (!entry) return res.status(404).json({ error: 'Entry not found' });
    res.json({ success: true, entry });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/journal/:id/permanent — hard delete an archived entry
router.delete('/:id/permanent', auth, async (req, res) => {
  try {
    const entry = await JournalEntry.findOneAndDelete({
      _id: req.params.id,
      userId: req.userId,
      isArchived: true,
    });
    if (!entry) return res.status(404).json({ error: 'Entry not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

const express = require('express');
const mongoose = require('mongoose');

const auth = require('../middleware/auth');
const NotificationHistory = require('../models/NotificationHistory');

const router = express.Router();

const serialize = (doc) => ({
  id: doc._id.toString(),
  type: doc.type,
  payload: doc.payload || {},
  isRead: !!doc.isRead,
  readAt: doc.readAt,
  createdAt: doc.createdAt,
});

router.get('/', auth, async (req, res) => {
  try {
    const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
    const offset = Math.max(0, Number(req.query.offset) || 0);
    const unread = String(req.query.unread || '').toLowerCase() === 'true';

    const filter = {
      recipient: req.userId,
    };
    if (unread) {
      filter.isRead = false;
    }

    const [rows, total, unreadCount] = await Promise.all([
      NotificationHistory.find(filter)
        .sort({ createdAt: -1 })
        .skip(offset)
        .limit(limit)
        .lean(),
      NotificationHistory.countDocuments(filter),
      NotificationHistory.countDocuments({ recipient: req.userId, isRead: false }),
    ]);

    res.json({
      items: rows.map(serialize),
      total,
      unreadCount,
      limit,
      offset,
      hasMore: offset + rows.length < total,
    });
  } catch (err) {
    console.error('Get notifications error', err);
    res.status(500).json({ error: 'Unable to fetch notifications' });
  }
});

router.post('/:id/read', auth, async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid notification id' });
    }

    const updated = await NotificationHistory.findOneAndUpdate(
      { _id: id, recipient: req.userId },
      { $set: { isRead: true, readAt: new Date() } },
      { new: true },
    ).lean();

    if (!updated) {
      return res.status(404).json({ error: 'Notification not found' });
    }

    res.json({ item: serialize(updated) });
  } catch (err) {
    console.error('Mark notification read error', err);
    res.status(500).json({ error: 'Unable to update notification' });
  }
});

router.post('/read-all', auth, async (req, res) => {
  try {
    const result = await NotificationHistory.updateMany(
      { recipient: req.userId, isRead: false },
      { $set: { isRead: true, readAt: new Date() } },
    );

    res.json({ updated: result.modifiedCount || 0 });
  } catch (err) {
    console.error('Mark all notifications read error', err);
    res.status(500).json({ error: 'Unable to update notifications' });
  }
});

router.delete('/:id', auth, async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid notification id' });
    }

    const removed = await NotificationHistory.findOneAndDelete({
      _id: id,
      recipient: req.userId,
    }).lean();

    if (!removed) {
      return res.status(404).json({ error: 'Notification not found' });
    }

    res.json({ status: 'deleted' });
  } catch (err) {
    console.error('Delete notification error', err);
    res.status(500).json({ error: 'Unable to delete notification' });
  }
});

module.exports = router;

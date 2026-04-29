const mongoose = require('mongoose');

const moodInsightSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    payload: {
      type: Object,
      default: {},
    },
    lastMoodDateKey: {
      type: String,
      default: null,
    },
    expiresAt: {
      type: Date,
      required: true,
    },
  },
  { timestamps: true }
);

moodInsightSchema.index({ userId: 1 }, { unique: true });
moodInsightSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('MoodInsight', moodInsightSchema);

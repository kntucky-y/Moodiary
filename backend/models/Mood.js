const mongoose = require('mongoose');

const moodLogSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    dateKey: { // YYYY-MM-DD
      type: String,
      required: true,
    },
    moodLevel: { // 1=Terrible, 2=Bad, 3=Okay, 4=Good, 5=Excellent
      type: Number,
      default: 3,
      min: 1,
      max: 5,
    },
    activities: {
      type: [String],
      default: [],
    },
    // moodScore  = moodLevel + sum of activity scores (set by calendar)
    moodScore: {
      type: Number,
      default: 0,
    },
    // taskScore  = points earned from daily task completions (set by home)
    taskScore: {
      type: Number,
      default: 0,
    },
    // score = moodScore + taskScore (combined total, computed by server)
    score: {
      type: Number,
      default: 0,
    },
  },
  { timestamps: true }
);

// One log per user per day
moodLogSchema.index({ userId: 1, dateKey: 1 }, { unique: true });

module.exports = mongoose.model('MoodLog', moodLogSchema);

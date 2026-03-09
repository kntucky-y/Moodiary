const mongoose = require('mongoose');

const moodSchema = new mongoose.Schema(
  {
    mood: {
      type: String,
      required: true,
      enum: ['happy', 'sad', 'angry', 'anxious', 'calm', 'excited', 'neutral'],
    },
    note: {
      type: String,
      default: '',
    },
    date: {
      type: Date,
      default: Date.now,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Mood', moodSchema);

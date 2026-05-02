const mongoose = require('mongoose');

const mbtiTestAttemptSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    mbtiType: {
      type: String,
      required: true,
      enum: [
        'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
        'ISTP', 'ISFP', 'INFP', 'INTP',
        'ESTP', 'ESFP', 'ENFP', 'ENTP',
        'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ',
      ],
    },
    answers: {
      type: [Number],
      required: true,
      validate: {
        validator: (value) => Array.isArray(value) && value.length === 30,
        message: 'MBTI attempts must contain exactly 30 answers',
      },
    },
    scores: {
      E: { type: Number, required: true },
      I: { type: Number, required: true },
      S: { type: Number, required: true },
      N: { type: Number, required: true },
      T: { type: Number, required: true },
      F: { type: Number, required: true },
      J: { type: Number, required: true },
      P: { type: Number, required: true },
    },
    schemaVersion: {
      type: Number,
      default: 1,
    },
  },
  { timestamps: true }
);

mbtiTestAttemptSchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('MbtiTestAttempt', mbtiTestAttemptSchema);

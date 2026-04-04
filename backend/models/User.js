const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
    },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
    },
    password: {
      type: String,
      required: function () {
        return this.provider === 'local';
      },
    },
    provider: {
      type: String,
      enum: ['local', 'google', 'facebook'],
      default: 'local',
    },
    providerId: {
      type: String,
      unique: true,
      sparse: true,
    },
    avatarUrl: String,
    bio: {
      type: String,
      default: '',
      maxlength: 500,
    },
    mbtiLatestType: {
      type: String,
      enum: [
        'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
        'ISTP', 'ISFP', 'INFP', 'INTP',
        'ESTP', 'ESFP', 'ENFP', 'ENTP',
        'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ',
      ],
      default: null,
    },
    mbtiLatestScores: {
      E: { type: Number, default: 0 },
      I: { type: Number, default: 0 },
      S: { type: Number, default: 0 },
      N: { type: Number, default: 0 },
      T: { type: Number, default: 0 },
      F: { type: Number, default: 0 },
      J: { type: Number, default: 0 },
      P: { type: Number, default: 0 },
    },
    mbtiLastTestedAt: {
      type: Date,
      default: null,
    },
    mbtiAttemptsCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    blockedUsers: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: 'User',
      default: [],
    },
    mutedUsers: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: 'User',
      default: [],
    },
    pushTokens: {
      type: [String],
      default: [],
    },
    resetToken: String,
    resetTokenExpires: Date,
  },
  { timestamps: true }
);

module.exports = mongoose.model('User', userSchema);

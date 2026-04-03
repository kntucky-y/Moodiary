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
    blockedUsers: {
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

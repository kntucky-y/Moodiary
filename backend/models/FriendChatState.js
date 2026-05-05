const mongoose = require('mongoose');

const friendChatStateSchema = new mongoose.Schema(
  {
    friendship: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Friendship',
      required: true,
      index: true,
    },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    clearedAt: {
      type: Date,
      default: null,
    },
  },
  { timestamps: true }
);

friendChatStateSchema.index({ friendship: 1, user: 1 }, { unique: true });

module.exports = mongoose.model('FriendChatState', friendChatStateSchema);

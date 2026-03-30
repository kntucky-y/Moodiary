const mongoose = require('mongoose');

const friendMessageSchema = new mongoose.Schema(
  {
    friendship: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Friendship',
      required: true,
    },
    sender: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    text: {
      type: String,
      required: true,
      trim: true,
    },
  },
  { timestamps: true }
);

friendMessageSchema.index({ friendship: 1, createdAt: 1 });

module.exports = mongoose.model('FriendMessage', friendMessageSchema);

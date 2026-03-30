const mongoose = require('mongoose');

const friendshipSchema = new mongoose.Schema(
  {
    members: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
      },
    ],
    pairKey: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },
    lastMessage: {
      text: String,
      sender: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
      },
      createdAt: Date,
    },
  },
  { timestamps: true }
);

friendshipSchema.index({ members: 1 });

module.exports = mongoose.model('Friendship', friendshipSchema);

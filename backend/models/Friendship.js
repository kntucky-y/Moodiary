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
    status: {
      type: String,
      enum: ['active', 'archived'],
      default: 'active',
      index: true,
    },
    endedAt: Date,
    lastMessage: {
      text: String,
      sender: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
      },
      createdAt: Date,
    },
    relationshipRole: {
      type: String,
      enum: ['friend', 'partner'],
      default: 'friend',
      index: true,
    },
    partnerRequestBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
  },
  { timestamps: true }
);

friendshipSchema.index({ members: 1 });

module.exports = mongoose.model('Friendship', friendshipSchema);

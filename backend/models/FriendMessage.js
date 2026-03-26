const mongoose = require('mongoose');

const { Schema } = mongoose;

const friendMessageSchema = new Schema(
  {
    friendshipId: {
      type: Schema.Types.ObjectId,
      ref: 'Friendship',
      required: true,
    },
    sender: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    text: {
      type: String,
      required: true,
      trim: true,
    },
    readBy: [{ type: Schema.Types.ObjectId, ref: 'User' }],
  },
  { timestamps: true }
);

friendMessageSchema.index({ friendshipId: 1, createdAt: -1 });

module.exports = mongoose.model('FriendMessage', friendMessageSchema);

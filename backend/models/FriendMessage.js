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
      trim: true,
      default: '',
    },
    type: {
      type: String,
      enum: ['text', 'image'],
      default: 'text',
      index: true,
    },
    imageUrl: {
      type: String,
      default: '',
      trim: true,
    },
    imageMeta: {
      width: Number,
      height: Number,
      size: Number,
      mimeType: String,
    },
    unsentAt: {
      type: Date,
      default: null,
    },
    unsentBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    deletedFor: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
      },
    ],
  },
  { timestamps: true }
);

friendMessageSchema.index({ friendship: 1, createdAt: 1 });
friendMessageSchema.index({ text: 'text' });

module.exports = mongoose.model('FriendMessage', friendMessageSchema);

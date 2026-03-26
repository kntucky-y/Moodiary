const mongoose = require('mongoose');

const { Schema, Types } = mongoose;

const lastMessageSchema = new Schema(
  {
    text: String,
    sender: { type: Schema.Types.ObjectId, ref: 'User' },
    createdAt: Date,
  },
  { _id: false }
);

const friendshipSchema = new Schema(
  {
    participants: {
      type: [{ type: Schema.Types.ObjectId, ref: 'User' }],
      validate: {
        validator: (arr) => Array.isArray(arr) && arr.length === 2,
        message: 'Friendship requires exactly 2 participants.',
      },
      required: true,
    },
    participantsKey: {
      type: String,
      unique: true,
      required: true,
    },
    initiator: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    status: {
      type: String,
      enum: ['pending', 'accepted', 'blocked'],
      default: 'pending',
    },
    lastMessage: lastMessageSchema,
  },
  { timestamps: true }
);

friendshipSchema.pre('validate', function preValidate(next) {
  if (this.participants && this.participants.length === 2) {
    const sorted = this.participants.map((id) => id.toString()).sort();
    this.participants = sorted.map((id) => new Types.ObjectId(id));
    this.participantsKey = sorted.join(':');
  }
  next();
});

module.exports = mongoose.model('Friendship', friendshipSchema);

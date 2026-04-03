const mongoose = require('mongoose');

const userReportSchema = new mongoose.Schema(
  {
    reporterId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    targetUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    reason: {
      type: String,
      required: true,
      trim: true,
      maxlength: 100,
    },
    details: {
      type: String,
      default: '',
      trim: true,
      maxlength: 1000,
    },
    status: {
      type: String,
      enum: ['open', 'reviewed', 'resolved'],
      default: 'open',
    },
  },
  { timestamps: true }
);

userReportSchema.index({ reporterId: 1, targetUserId: 1, createdAt: -1 });

module.exports = mongoose.model('UserReport', userReportSchema);
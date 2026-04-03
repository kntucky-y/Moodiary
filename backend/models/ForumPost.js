const mongoose = require('mongoose');

const forumCommentSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    authorName: {
      type: String,
      required: true,
      trim: true,
    },
    authorAvatarUrl: {
      type: String,
      default: '',
      trim: true,
    },
    isAnonymous: {
      type: Boolean,
      default: true,
    },
    text: {
      type: String,
      required: true,
      trim: true,
      maxlength: 500,
    },
    moodAsset: {
      type: String,
      default: 'assets/okay.png',
    },
  },
  { timestamps: true }
);

const forumReportSchema = new mongoose.Schema(
  {
    reporterId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    reason: {
      type: String,
      required: true,
      trim: true,
      maxlength: 300,
    },
    details: {
      type: String,
      default: '',
      trim: true,
      maxlength: 1000,
    },
  },
  { timestamps: true }
);

const forumPostSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    authorName: {
      type: String,
      required: true,
      trim: true,
    },
    authorAvatarUrl: {
      type: String,
      default: '',
      trim: true,
    },
    companionId: {
      type: Number,
      default: 1,
    },
    title: {
      type: String,
      required: true,
      trim: true,
      maxlength: 120,
    },
    content: {
      type: String,
      required: true,
      trim: true,
      maxlength: 2000,
    },
    isAnonymous: {
      type: Boolean,
      default: true,
    },
    likedBy: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
      },
    ],
    comments: [forumCommentSchema],
    reports: [forumReportSchema],
  },
  { timestamps: true }
);

forumPostSchema.index({ createdAt: -1 });

module.exports = mongoose.model('ForumPost', forumPostSchema);
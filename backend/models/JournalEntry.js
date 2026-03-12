const mongoose = require('mongoose');

const journalEntrySchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
    },
    content: {
      type: String,
      required: true,
    },
    // tag is one of: terrible | bad | okay | good | excellent
    tag: {
      type: String,
      default: 'okay',
    },
    isArchived: {
      type: Boolean,
      default: false,
      index: true,
    },
    archivedAt: {
      type: Date,
      default: null,
    },
  },
  { timestamps: true }
);

journalEntrySchema.index({ userId: 1, isArchived: 1, createdAt: -1 });

module.exports = mongoose.model('JournalEntry', journalEntrySchema);

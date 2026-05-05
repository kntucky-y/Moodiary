const mongoose = require('mongoose');
require('dotenv').config({ path: '.env' });

const FriendMessage = require('../models/FriendMessage');

async function run() {
  const uri = process.env.MONGO_URI;
  if (!uri) {
    throw new Error('MONGO_URI is not set');
  }

  await mongoose.connect(uri);

  const filter = {
    $or: [
      { type: 'image' },
      { imageUrl: { $exists: true, $ne: '' } },
    ],
  };

  const result = await FriendMessage.deleteMany(filter);
  console.log(`Deleted ${result.deletedCount} image message(s).`);

  await mongoose.disconnect();
}

run().catch((err) => {
  console.error('Migration failed:', err.message);
  process.exitCode = 1;
});

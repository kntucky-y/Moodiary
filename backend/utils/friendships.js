const mongoose = require('mongoose');
const Friendship = require('../models/Friendship');

const isValidObjectId = (value) => mongoose.Types.ObjectId.isValid(value);

const buildPairKey = (a, b) => [a.toString(), b.toString()].sort().join(':');

const ensureFriendshipAccess = async (friendshipId, userId) => {
  if (!isValidObjectId(friendshipId)) {
    const err = new Error('Invalid friendship id');
    err.status = 400;
    throw err;
  }

  const friendship = await Friendship.findById(friendshipId);
  if (!friendship) {
    const err = new Error('Friendship not found');
    err.status = 404;
    throw err;
  }

  const allowed = friendship.members.some(
    (member) => member.toString() === userId.toString(),
  );
  if (!allowed) {
    const err = new Error('You are not part of this friendship');
    err.status = 403;
    throw err;
  }

  return friendship;
};

module.exports = {
  isValidObjectId,
  buildPairKey,
  ensureFriendshipAccess,
};

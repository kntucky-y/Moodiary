const DEFAULT_MESSAGE = 'Too many requests. Please try again later.';

const buckets = new Map();
let cleanupTimer = null;

const startCleanup = () => {
  if (cleanupTimer) return;
  cleanupTimer = setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of buckets.entries()) {
      if (entry.resetAt <= now) {
        buckets.delete(key);
      }
    }
  }, 60 * 1000);

  if (typeof cleanupTimer.unref === 'function') {
    cleanupTimer.unref();
  }
};

const defaultKeyGenerator = (req) => {
  if (req.userId) {
    return String(req.userId);
  }

  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }

  return req.ip || req.socket?.remoteAddress || 'unknown';
};

const createRateLimiter = ({
  windowMs = 15 * 60 * 1000,
  max = 60,
  message = DEFAULT_MESSAGE,
  keyGenerator = defaultKeyGenerator,
  skip,
} = {}) => {
  startCleanup();
  const limiterId = Math.random().toString(36).slice(2);

  return (req, res, next) => {
    if (typeof skip === 'function' && skip(req)) {
      return next();
    }

    const scope = keyGenerator(req) || defaultKeyGenerator(req);
    const bucketKey = `${limiterId}:${scope}`;
    const now = Date.now();
    let entry = buckets.get(bucketKey);

    if (!entry || entry.resetAt <= now) {
      entry = {
        count: 0,
        resetAt: now + windowMs,
      };
      buckets.set(bucketKey, entry);
    }

    entry.count += 1;

    const remaining = Math.max(0, max - entry.count);
    res.setHeader('X-RateLimit-Limit', String(max));
    res.setHeader('X-RateLimit-Remaining', String(remaining));
    res.setHeader('X-RateLimit-Reset', String(Math.ceil(entry.resetAt / 1000)));

    if (entry.count > max) {
      res.setHeader('Retry-After', String(Math.ceil((entry.resetAt - now) / 1000)));
      return res.status(429).json({ error: message });
    }

    return next();
  };
};

module.exports = {
  createRateLimiter,
};
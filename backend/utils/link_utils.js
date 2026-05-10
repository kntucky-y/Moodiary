const REDIRECT_PARAM_KEYS = ['url', 'u', 'q', 'target', 'dest', 'destination', 'redirect'];

const stripTrailingPunctuation = (value) =>
  value.replace(/[)\],.;!?]+$/g, '').trim();

const unwrapRedirectUrl = (candidate) => {
  let current = candidate;
  for (let i = 0; i < 3; i += 1) {
    let parsed;
    try {
      parsed = new URL(current);
    } catch (_) {
      return current;
    }

    let next = null;
    for (const key of REDIRECT_PARAM_KEYS) {
      const raw = parsed.searchParams.get(key);
      if (!raw) continue;
      const decoded = decodeURIComponent(raw).trim();
      if (/^https?:\/\//i.test(decoded)) {
        next = decoded;
        break;
      }
    }

    if (!next || next === current) {
      return current;
    }
    current = next;
  }
  return current;
};

const sanitizeExternalUrl = (rawValue) => {
  const text = String(rawValue || '').trim();
  if (!text) return null;

  const noMarkdown = text
    .replace(/^<|>$/g, '')
    .replace(/^\[([^\]]+)\]\(([^)]+)\)$/g, '$2')
    .trim();
  const noTrailing = stripTrailingPunctuation(noMarkdown);
  const withScheme = /^https?:\/\//i.test(noTrailing)
    ? noTrailing
    : `https://${noTrailing}`;
  const unwrapped = unwrapRedirectUrl(withScheme);

  try {
    const parsed = new URL(unwrapped);
    if (!['http:', 'https:'].includes(parsed.protocol)) return null;
    return parsed.toString();
  } catch (_) {
    return null;
  }
};

module.exports = {
  sanitizeExternalUrl,
  isLikelyReachableUrl: async (rawUrl) => {
    const normalized = sanitizeExternalUrl(rawUrl);
    if (!normalized) return false;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 7000);
    try {
      let response = await fetch(normalized, {
        method: 'HEAD',
        redirect: 'follow',
        signal: controller.signal,
      });

      if (response.status === 405 || response.status === 403) {
        response = await fetch(normalized, {
          method: 'GET',
          redirect: 'follow',
          signal: controller.signal,
          headers: { Range: 'bytes=0-1024' },
        });
      }

      return response.ok;
    } catch (_) {
      return false;
    } finally {
      clearTimeout(timeout);
    }
  },
};

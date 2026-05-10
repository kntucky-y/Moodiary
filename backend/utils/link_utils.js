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
};

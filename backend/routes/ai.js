const express = require('express');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const router = express.Router();
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const MoodLog = require('../models/Mood');
const MoodInsight = require('../models/MoodInsight');
const JournalEntry = require('../models/JournalEntry');

const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_BOOSTERS = 3;
const AI_TASK_COUNT = 3;
const JOURNAL_LOOKBACK = 3;
const JOURNAL_SNIPPET_MAX = 180;
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-1.5-flash-latest';
const GEMINI_FALLBACK_MODELS = [
  GEMINI_MODEL,
  'gemini-1.5-flash-latest',
  'gemini-1.5-flash-002',
  'gemini-1.5-flash-001',
  'gemini-1.5-pro-latest',
];

const geminiApiKey =
  process.env.GEMINI_API_KEY || process.env.GOOGLE_GENERATIVE_AI_API_KEY;
const geminiClient = geminiApiKey ? new GoogleGenerativeAI(geminiApiKey) : null;

const isModelNotFoundError = (err) => {
  const message = (err && err.message ? err.message : '').toLowerCase();
  return message.includes('not found') || message.includes('not supported');
};

const generateWithFallback = async (request) => {
  if (!geminiClient) return null;
  const tried = new Set();
  let lastError;
  for (const modelName of GEMINI_FALLBACK_MODELS) {
    const name = (modelName || '').trim();
    if (!name || tried.has(name)) continue;
    tried.add(name);
    const model = geminiClient.getGenerativeModel({ model: name });
    try {
      return await model.generateContent(request);
    } catch (err) {
      lastError = err;
      if (!isModelNotFoundError(err)) {
        throw err;
      }
    }
  }
  throw lastError;
};

const aiLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: 'Too many AI requests. Please wait a moment and try again.',
  keyGenerator: (req) => `ai:${req.userId || req.ip}`,
});

router.use(auth, aiLimiter);

const promptStyleGuide =
  'Reply like a supportive, upbeat coach in 1-2 sentences. Keep it under 220 characters and under 34 words. Avoid lists, disclaimers, and medical advice. Ask at most one short follow-up question when it naturally fits.';

const fallbackReply =
  'I see your recent mood pattern. What has been helping you feel even a little better lately?';

const fallbackTasks = [
  {
    title: 'Take a 10-minute walk',
    description: 'Step outside and walk for 10 minutes to reset your mood.',
    points: 10,
  },
  {
    title: 'Write 3 gratitudes',
    description: 'Jot down three small wins or moments you appreciate today.',
    points: 15,
  },
  {
    title: 'Deep breathing (4-7-8)',
    description: 'Do 3 rounds of 4-7-8 breathing to calm your body.',
    points: 10,
  },
];

const toDateKey = (date) => {
  const y = date.getFullYear().toString().padStart(4, '0');
  const m = (date.getMonth() + 1).toString().padStart(2, '0');
  const d = date.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${d}`;
};

const getRecentDateKeys = (days) => {
  const keys = [];
  const now = new Date();
  for (let i = days - 1; i >= 0; i -= 1) {
    const date = new Date(now);
    date.setDate(now.getDate() - i);
    keys.push(toDateKey(date));
  }
  return keys;
};

const moodIndexForLog = (log) => {
  if (!log) return null;
  const moodLevel = Number(log.moodLevel || 0);
  const activityScore = Number(log.activityScore || 0);
  if (!Number.isFinite(moodLevel) || moodLevel <= 0) return null;
  const base = moodLevel * 2;
  const bonus = Math.round(activityScore / 2);
  const score = Math.max(1, Math.min(10, base + bonus));
  return score;
};

const average = (values) => {
  const valid = values.filter((v) => typeof v === 'number');
  if (!valid.length) return null;
  const sum = valid.reduce((acc, v) => acc + v, 0);
  return sum / valid.length;
};

const trendDirection = (delta) => {
  if (delta >= 0.2) return 'improving';
  if (delta <= -0.2) return 'declining';
  return 'steady';
};

const formatPercent = (value) => {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value);
};

const buildBoosters = (logs, baselineAvg) => {
  if (!logs.length || baselineAvg == null) {
    return [
      { activity: 'Exercise', reason: 'Movement often lifts mood quickly.' },
      { activity: 'Journaling', reason: 'Writing it out can ease mental load.' },
      { activity: 'Good Sleep', reason: 'Rest helps stabilize mood swings.' },
    ];
  }

  const activityMap = new Map();
  for (const log of logs) {
    const index = moodIndexForLog(log);
    if (index == null) continue;
    for (const activity of log.activities || []) {
      if (!activityMap.has(activity)) {
        activityMap.set(activity, { total: 0, count: 0 });
      }
      const entry = activityMap.get(activity);
      entry.total += index;
      entry.count += 1;
    }
  }

  const ranked = Array.from(activityMap.entries())
    .map(([activity, stats]) => {
      const avg = stats.count ? stats.total / stats.count : null;
      if (avg == null) return null;
      return { activity, delta: avg - baselineAvg, avg };
    })
    .filter((item) => item && item.delta > 0.2)
    .sort((a, b) => b.delta - a.delta)
    .slice(0, MAX_BOOSTERS);

  if (!ranked.length) {
    return [
      { activity: 'Exercise', reason: 'Movement often lifts mood quickly.' },
      { activity: 'Journaling', reason: 'Writing it out can ease mental load.' },
      { activity: 'Good Sleep', reason: 'Rest helps stabilize mood swings.' },
    ];
  }

  return ranked.map((item) => ({
    activity: item.activity,
    reason: `Your mood tends to run higher on ${item.activity.toLowerCase()} days.`,
  }));
};

const normalizeSnippet = (text, maxLen) => {
  const clean = (text || '')
    .replace(/\s+/g, ' ')
    .replace(/[\r\n]+/g, ' ')
    .trim();
  if (!clean) return '';
  if (clean.length <= maxLen) return clean;
  if (maxLen <= 3) return clean.slice(0, maxLen);
  return `${clean.slice(0, maxLen - 3)}...`;
};

const summarizeActivities = (logs) => {
  const counts = new Map();
  for (const log of logs) {
    for (const activity of log.activities || []) {
      const key = String(activity).trim();
      if (!key) continue;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
  }
  return Array.from(counts.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([name]) => name);
};

const buildJournalSnippets = (entries) =>
  entries.map((entry) => {
    const createdAt = entry.createdAt
      ? new Date(entry.createdAt).toISOString().slice(0, 10)
      : 'recent';
    const title = normalizeSnippet(entry.title, 60) || 'Untitled';
    const excerpt = normalizeSnippet(entry.content, JOURNAL_SNIPPET_MAX);
    const tag = entry.tag || 'okay';
    return `${createdAt} [${tag}] ${title} — ${excerpt}`;
  });

const buildPrompt = ({ last7, trendLabel, activities, journalSnippets }) => {
  const last7Formatted = last7
    .map((v) => (v == null ? '-' : String(v)))
    .join(', ');
  const activityLine = activities.length
    ? `Recent activities: ${activities.join(', ')}.`
    : 'Recent activities: none logged.';
  const journalLine = journalSnippets.length
    ? `Recent journal notes: ${journalSnippets.join(' | ')}.`
    : 'Recent journal notes: none available.';
  return [
    `Last 7 days mood index: ${last7Formatted}. Trend: ${trendLabel}.`,
    activityLine,
    journalLine,
    `Return JSON only with keys: aiMessage (string) and tasks (array of ${AI_TASK_COUNT} items).`,
    'Each task must be a concrete, time-boxed action for today (5-30 minutes), start with a verb, and be based on the recent mood, activities, or journal notes.',
    'Avoid goals, streaks, or vague intentions. No lists or extra keys in the JSON.',
    'Each task needs title, description, and points (5-20).',
  ].join('\n');
};

const parseAiJson = (raw) => {
  if (!raw) return null;
  const clean = raw
    .replace(/```json|```/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
  try {
    return JSON.parse(clean);
  } catch (_) {
    return null;
  }
};

const normalizeTasks = (tasks) => {
  if (!Array.isArray(tasks)) return [];
  const normalized = tasks
    .map((task) => {
      if (!task || typeof task !== 'object') return null;
      const title = (task.title || '').toString().trim();
      const description = (task.description || '').toString().trim();
      const points = Number(task.points);
      if (!title || !description) return null;
      const safePoints = Number.isFinite(points)
        ? Math.min(20, Math.max(5, Math.round(points)))
        : 10;
      return { title, description, points: safePoints };
    })
    .filter(Boolean)
    .slice(0, AI_TASK_COUNT);

  return normalized;
};

const normalizeMessage = (text) => {
  const clean = (text || '')
    .replace(/\s+/g, ' ')
    .replace(/\*\*|__|`/g, '')
    .trim();
  return clean.length > 0 ? clean : fallbackReply;
};

const getAiBundle = async (message) => {
  if (!geminiClient) return null;
  try {
    const result = await generateWithFallback({
      contents: [
        {
          role: 'user',
          parts: [{ text: `${promptStyleGuide}\n\n${message}` }],
        },
      ],
      generationConfig: {
        temperature: 0.45,
        maxOutputTokens: 420,
        responseMimeType: 'application/json',
      },
    });

    const reply = result && result.response ? result.response.text() || '' : '';
    const parsed = parseAiJson(reply);
    if (!parsed) return null;
    const tasks = normalizeTasks(parsed.tasks);
    if (!tasks.length) return null;
    return { aiMessage: normalizeMessage(parsed.aiMessage), tasks };
  } catch (err) {
    console.error('Gemini AI insights error:', err.message);
    return null;
  }
};

router.get('/mood-insights', async (req, res) => {
  try {
    const now = new Date();
    const latestLog = await MoodLog.findOne({ userId: req.userId })
      .sort({ dateKey: -1 })
      .select('dateKey')
      .lean();
    const lastMoodDateKey = latestLog?.dateKey || null;

    const cached = await MoodInsight.findOne({ userId: req.userId }).lean();
    if (cached && cached.expiresAt && cached.expiresAt > now) {
      if (cached.lastMoodDateKey === lastMoodDateKey && cached.payload) {
        return res.json({
          ...cached.payload,
          cachedAt: cached.createdAt,
        });
      }
    }

    const keys = getRecentDateKeys(14);
    const logs = await MoodLog.find({
      userId: req.userId,
      dateKey: { $in: keys },
    }).lean();

    const journalEntries = await JournalEntry.find({
      userId: req.userId,
      isArchived: { $ne: true },
    })
      .sort({ createdAt: -1 })
      .limit(JOURNAL_LOOKBACK)
      .select('title content tag createdAt')
      .lean();

    const logByKey = new Map();
    for (const log of logs) {
      logByKey.set(log.dateKey, log);
    }

    const last7Keys = keys.slice(7);
    const prev7Keys = keys.slice(0, 7);
    const last7Values = last7Keys.map((key) => moodIndexForLog(logByKey.get(key)));
    const prev7Values = prev7Keys.map((key) => moodIndexForLog(logByKey.get(key)));

    const lastAvg = average(last7Values);
    const prevAvg = average(prev7Values);
    const baseline = average([...last7Values, ...prev7Values]);

    let percent = 0;
    let direction = 'steady';
    if (lastAvg != null && prevAvg != null && prevAvg > 0) {
      const delta = (lastAvg - prevAvg) / prevAvg;
      percent = formatPercent(delta * 100);
      direction = trendDirection(lastAvg - prevAvg);
    }

    const boosters = buildBoosters(logs, baseline);
    const trendLabel = `${direction}${percent ? ` ${Math.abs(percent)}%` : ''}`.trim();
    const activities = summarizeActivities(logs);
    const journalSnippets = buildJournalSnippets(journalEntries);
    const prompt = buildPrompt({
      last7: last7Values,
      trendLabel,
      activities,
      journalSnippets,
    });
    const aiBundle = await getAiBundle(prompt);
    const cachedTasks = cached?.payload?.tasks;
    const cachedMessage = cached?.payload?.aiMessage;
    const hasCachedTasks = Array.isArray(cachedTasks) && cachedTasks.length;

    const cachedNormalized = hasCachedTasks ? normalizeTasks(cachedTasks) : [];
    const finalTasks = aiBundle?.tasks?.length
      ? aiBundle.tasks
      : cachedNormalized.length
      ? cachedNormalized
      : fallbackTasks;
    const finalMessage = aiBundle?.aiMessage || cachedMessage || fallbackReply;

    const payload = {
      last7: last7Values,
      trendPercent: percent,
      trendDirection: direction,
      aiMessage: finalMessage,
      tasks: finalTasks,
      boosters,
      lastMoodDateKey,
      generatedAt: now.toISOString(),
      aiProvider: aiBundle ? 'gemini' : 'fallback',
    };

    await MoodInsight.findOneAndUpdate(
      { userId: req.userId },
      {
        payload,
        lastMoodDateKey,
        expiresAt: new Date(now.getTime() + CACHE_TTL_MS),
      },
      { upsert: true, new: true }
    );

    res.json(payload);
  } catch (err) {
    res.status(500).json({ error: 'Unable to build AI insights right now.' });
  }
});

module.exports = router;

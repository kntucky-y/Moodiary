const express = require('express');
const Groq = require('groq-sdk');
const router = express.Router();
const auth = require('../middleware/auth');
const MoodLog = require('../models/Mood');
const MoodInsight = require('../models/MoodInsight');

const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_BOOSTERS = 3;

const groq = process.env.GROQ_API_KEY
  ? new Groq({ apiKey: process.env.GROQ_API_KEY })
  : null;

const promptStyleGuide =
  'Reply like a supportive, upbeat coach in 1-2 sentences. Keep it under 220 characters and under 34 words. Avoid lists, disclaimers, and medical advice. Ask at most one short follow-up question when it naturally fits.';

const fallbackReply =
  'I see your recent mood pattern. What has been helping you feel even a little better lately?';

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

const buildPrompt = ({ last7, trendLabel }) => {
  const last7Formatted = last7
    .map((v) => (v == null ? '-' : String(v)))
    .join(', ');
  return `Last 7 days: ${last7Formatted}. Trend: ${trendLabel}. Respond with a short supportive insight.`;
};

const getAiReply = async (message) => {
  if (!groq) return fallbackReply;
  try {
    const completion = await groq.chat.completions.create({
      model: 'llama-3.3-70b-versatile',
      messages: [
        { role: 'system', content: promptStyleGuide },
        { role: 'user', content: message },
      ],
      max_tokens: 120,
    });

    const reply = completion.choices[0].message.content || '';
    const clean = reply.replace(/\s+/g, ' ').replace(/\*\*|__|`/g, '').trim();
    return clean.length > 0 ? clean : fallbackReply;
  } catch (err) {
    return fallbackReply;
  }
};

router.get('/mood-insights', auth, async (req, res) => {
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
    const prompt = buildPrompt({ last7: last7Values, trendLabel });
    const aiMessage = await getAiReply(prompt);

    const payload = {
      last7: last7Values,
      trendPercent: percent,
      trendDirection: direction,
      aiMessage,
      boosters,
      lastMoodDateKey,
      generatedAt: now.toISOString(),
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

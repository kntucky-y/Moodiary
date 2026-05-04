const express = require('express');
const jwt = require('jsonwebtoken');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const router = express.Router();

const MoodLog = require('../models/Mood');
const JournalEntry = require('../models/JournalEntry');
const { createRateLimiter } = require('../middleware/rate_limit');
const { getNearbyMentalHealthClinics } = require('../utils/clinic_search');

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

const resourceCatalog = [
  {
    id: 'anxiety_mayo',
    title: 'Understanding Anxiety',
    description:
      'A comprehensive guide to recognizing and managing anxiety symptoms in daily life.',
    category: 'Mental Health',
    url: 'https://www.mayoclinic.org/diseases-conditions/anxiety-disorders/symptoms-causes/syc-20350961',
    icon: 'anxiety',
    tags: ['anxiety', 'worry', 'stress', 'panic', 'overthinking'],
  },
  {
    id: 'meditation_headspace',
    title: 'Meditation Basics',
    description:
      'Learn foundational meditation techniques to reduce stress and improve focus.',
    category: 'Mindfulness',
    url: 'https://www.headspace.com/work/meditation-for-beginners',
    icon: 'meditation',
    tags: ['mindfulness', 'stress', 'focus', 'calm', 'breathing'],
  },
  {
    id: 'sleep_foundation',
    title: 'Sleep Hygiene Tips',
    description:
      'Improve your sleep quality with proven sleep hygiene practices and bedtime routines.',
    category: 'Wellness',
    url: 'https://www.sleepfoundation.org/sleep-hygiene',
    icon: 'sleep',
    tags: ['sleep', 'fatigue', 'tired', 'routine', 'rest'],
  },
  {
    id: 'depression_samhsa',
    title: 'Coping with Depression',
    description:
      'Strategies and support options for difficult low-mood periods and mental health help-seeking.',
    category: 'Mental Health',
    url: 'https://www.samhsa.gov/find-help/national-helpline',
    icon: 'depression',
    tags: ['sad', 'depression', 'low mood', 'helpline', 'support'],
  },
  {
    id: 'breathing_verywellmind',
    title: 'Breathing Exercises',
    description:
      'Step-by-step breathing techniques to calm your mind and reduce racing thoughts.',
    category: 'Mindfulness',
    url: 'https://www.verywellmind.com/breathing-exercises-for-anxiety-3144786',
    icon: 'breathing',
    tags: ['breathing', 'anxiety', 'panic', 'calm', 'stress'],
  },
  {
    id: 'exercise_mental_health_foundation',
    title: 'Exercise and Mental Health',
    description:
      'How regular physical activity can support mood, stress relief, and emotional well-being.',
    category: 'Wellness',
    url: 'https://www.mentalhealth.org/our-work/mental-health-movement/exercise',
    icon: 'exercise',
    tags: ['exercise', 'movement', 'energy', 'mood', 'stress'],
  },
  {
    id: 'nutrition_psychiatry',
    title: 'Nutrition for Mood',
    description:
      'Discover foods and nutrients that support emotional health and brain function.',
    category: 'Wellness',
    url: 'https://www.psychiatry.org/patients-families/what-is-mental-illness/eating-disorders-and-mental-health',
    icon: 'nutrition',
    tags: ['nutrition', 'food', 'mood', 'wellness', 'energy'],
  },
  {
    id: 'social_connection_apa',
    title: 'Social Connection Matters',
    description:
      'The importance of maintaining healthy relationships and social bonds for mental health.',
    category: 'Social',
    url: 'https://www.apa.org/science/about/psa/social-connection',
    icon: 'social',
    tags: ['lonely', 'social', 'friends', 'support', 'connection'],
  },
  {
    id: 'grounding_healthline',
    title: 'Grounding Techniques',
    description:
      'Practical grounding methods for moments when emotions feel intense or hard to manage.',
    category: 'Mindfulness',
    url: 'https://www.healthline.com/health/grounding-techniques',
    icon: 'breathing',
    tags: ['grounding', 'overwhelmed', 'panic', 'stress', 'anxiety'],
  },
  {
    id: 'anger_apa',
    title: 'Controlling Anger Before It Controls You',
    description:
      'Healthy ways to understand anger signals and respond without escalating the moment.',
    category: 'Mental Health',
    url: 'https://www.apa.org/topics/anger/control',
    icon: 'anxiety',
    tags: ['anger', 'irritated', 'mad', 'conflict', 'stress'],
  },
  {
    id: 'self_compassion_berkeley',
    title: 'Self-Compassion Break',
    description:
      'A short guided practice for responding to yourself with more patience and care.',
    category: 'Mindfulness',
    url: 'https://ggia.berkeley.edu/practice/self_compassion_break',
    icon: 'meditation',
    tags: ['self compassion', 'shame', 'sad', 'stress', 'kindness'],
  },
  {
    id: 'stress_cdc',
    title: 'Coping with Stress',
    description:
      'Simple, practical actions for handling stress and knowing when to seek extra support.',
    category: 'Mental Health',
    url: 'https://www.cdc.gov/mental-health/living-with/index.html',
    icon: 'anxiety',
    tags: ['stress', 'overwhelmed', 'support', 'coping', 'mental health'],
  },
];

const categories = ['Mental Health', 'Mindfulness', 'Wellness', 'Social'];

const personalizedResourcesLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: 'Too many resource requests. Please wait a moment and try again.',
  keyGenerator: (req) => `resources:${parseOptionalUserId(req) || req.ip}`,
});

const normalizeSnippet = (text, maxLen = 140) => {
  const clean = (text || '').replace(/\s+/g, ' ').trim();
  if (!clean) return '';
  return clean.length <= maxLen ? clean : `${clean.slice(0, maxLen - 3)}...`;
};

const parseOptionalUserId = (req) => {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return null;
  try {
    const decoded = jwt.verify(header.slice(7), process.env.JWT_SECRET);
    return decoded.userId || null;
  } catch (_) {
    return null;
  }
};

const moodIndexForLog = (log) => {
  if (!log) return null;
  const moodLevel = Number(log.moodLevel || 0);
  const activityScore = Number(log.activityScore || 0);
  if (!Number.isFinite(moodLevel) || moodLevel <= 0) return null;
  return Math.max(1, Math.min(10, moodLevel * 2 + Math.round(activityScore / 2)));
};

const buildUserResourceContext = async (userId) => {
  if (!userId) return null;

  const [logs, journals] = await Promise.all([
    MoodLog.find({ userId }).sort({ dateKey: -1 }).limit(14).lean(),
    JournalEntry.find({ userId, isArchived: { $ne: true } })
      .sort({ createdAt: -1 })
      .limit(4)
      .select('title content tag createdAt')
      .lean(),
  ]);

  if (!logs.length && !journals.length) return null;

  const moodValues = logs
    .map((log) => moodIndexForLog(log))
    .filter((value) => value != null);
  const avgMood = moodValues.length
    ? moodValues.reduce((sum, value) => sum + value, 0) / moodValues.length
    : null;
  const activities = Array.from(
    logs.reduce((map, log) => {
      for (const activity of log.activities || []) {
        const key = String(activity).trim();
        if (key) map.set(key, (map.get(key) || 0) + 1);
      }
      return map;
    }, new Map())
  )
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([activity]) => activity);

  const journalSnippets = journals.map((entry) => {
    const date = entry.createdAt
      ? new Date(entry.createdAt).toISOString().slice(0, 10)
      : 'recent';
    const title = normalizeSnippet(entry.title, 50) || 'Untitled';
    const content = normalizeSnippet(entry.content, 140);
    return `${date} [${entry.tag || 'okay'}] ${title}: ${content}`;
  });

  return {
    avgMood: avgMood == null ? null : Number(avgMood.toFixed(1)),
    recentMoodIndexes: logs
      .slice(0, 7)
      .map((log) => moodIndexForLog(log))
      .reverse(),
    activities,
    journalSnippets,
  };
};

const parseAiJson = (raw) => {
  if (!raw) return null;
  const clean = raw.replace(/```json|```/gi, '').trim();
  try {
    return JSON.parse(clean);
  } catch (_) {
    return null;
  }
};

const scoreResource = (resource, context) => {
  if (!context) return 0;
  const haystack = [
    ...(context.activities || []),
    ...(context.journalSnippets || []),
  ]
    .join(' ')
    .toLowerCase();

  let score = 0;
  for (const tag of resource.tags) {
    if (haystack.includes(tag.toLowerCase())) score += 3;
  }
  if (context.avgMood != null && context.avgMood <= 4) {
    if (resource.tags.some((tag) => ['sad', 'depression', 'support', 'self compassion'].includes(tag))) {
      score += 2;
    }
  }
  if (context.avgMood != null && context.avgMood >= 7) {
    if (resource.tags.some((tag) => ['exercise', 'social', 'wellness'].includes(tag))) {
      score += 1;
    }
  }
  return score;
};

const fallbackPersonalize = (resources, context) => {
  return resources
    .map((resource) => ({
      ...resource,
      score: scoreResource(resource, context),
      recommendationReason: context
        ? 'Suggested from your recent mood and journal patterns.'
        : 'A reliable guide from Moodiary resources.',
    }))
    .sort((a, b) => b.score - a.score || a.title.localeCompare(b.title))
    .map((resource, index) => ({
      ...resource,
      featured: index < 3,
      score: undefined,
    }));
};

const getGeminiResourceOrder = async (context) => {
  if (!geminiClient || !context) return null;

  const catalogForPrompt = resourceCatalog.map((resource) => ({
    id: resource.id,
    title: resource.title,
    category: resource.category,
    tags: resource.tags,
  }));

  const prompt = [
    'You personalize Moodiary mental health resources.',
    'Choose the most relevant resource IDs from this vetted catalog only. Do not invent IDs or URLs.',
    'Return JSON only: {"recommendations":[{"id":"resource_id","reason":"short reason under 90 chars"}]}',
    'Prioritize practical, non-medical self-care support based on the user context.',
    `User context: ${JSON.stringify(context)}`,
    `Catalog: ${JSON.stringify(catalogForPrompt)}`,
  ].join('\n');

  try {
    const result = await generateWithFallback({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.35,
        maxOutputTokens: 520,
        responseMimeType: 'application/json',
      },
    });
    const parsed = parseAiJson(
      result && result.response ? result.response.text() : '',
    );
    const recs = Array.isArray(parsed?.recommendations)
      ? parsed.recommendations
      : [];
    const validIds = new Set(resourceCatalog.map((resource) => resource.id));
    return recs
      .map((rec) => ({
        id: String(rec.id || '').trim(),
        reason: normalizeSnippet(rec.reason, 90),
      }))
      .filter((rec) => validIds.has(rec.id));
  } catch (err) {
    console.error('Gemini resources error:', err.message);
    return null;
  }
};

const applyRecommendations = (resources, recommendations, context) => {
  if (!recommendations?.length) {
    return fallbackPersonalize(resources, context);
  }

  const byId = new Map(resources.map((resource) => [resource.id, resource]));
  const used = new Set();
  const ordered = [];

  for (const recommendation of recommendations) {
    const resource = byId.get(recommendation.id);
    if (!resource || used.has(resource.id)) continue;
    used.add(resource.id);
    ordered.push({
      ...resource,
      featured: ordered.length < 3,
      recommendationReason:
        recommendation.reason || 'Suggested from your recent mood patterns.',
    });
  }

  for (const resource of fallbackPersonalize(resources, context)) {
    if (used.has(resource.id)) continue;
    ordered.push({ ...resource, featured: false });
  }

  return ordered;
};

const toPublicResource = (resource) => {
  const { tags, score, ...publicResource } = resource;
  return publicResource;
};

// GET /api/resources - Get AI-personalized, vetted mental health resources
router.get('/', personalizedResourcesLimiter, async (req, res) => {
  try {
    const userId = parseOptionalUserId(req);
    const context = await buildUserResourceContext(userId);
    const recommendations = await getGeminiResourceOrder(context);
    const personalized = applyRecommendations(
      resourceCatalog,
      recommendations,
      context
    );

    const { category } = req.query;
    const filtered = category
      ? personalized.filter(
          (resource) =>
            resource.category.toLowerCase() === String(category).toLowerCase()
        )
      : personalized;

    res.json({
      resources: filtered.map(toPublicResource),
      total: filtered.length,
      personalized: Boolean(context),
      aiProvider: recommendations?.length ? 'gemini' : 'fallback',
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    console.error('Get resources error', err);
    res.status(500).json({ error: 'Unable to fetch resources' });
  }
});

// GET /api/resources/categories - Get available resource categories
router.get('/categories/list', async (req, res) => {
  try {
    res.json({ categories });
  } catch (err) {
    console.error('Get categories error', err);
    res.status(500).json({ error: 'Unable to fetch categories' });
  }
});

// GET /api/resources/clinics/nearby - Get nearby mental health clinics from live map data
router.get('/clinics/nearby', async (req, res) => {
  try {
    const payload = await getNearbyMentalHealthClinics({
      lat: req.query.lat,
      lng: req.query.lng,
      radius: req.query.radius,
      limit: req.query.limit,
    });

    res.json(payload);
  } catch (err) {
    console.error('Get nearby clinics error', err);
    res
      .status(400)
      .json({ error: err.message || 'Unable to fetch nearby clinics' });
  }
});

module.exports = router;

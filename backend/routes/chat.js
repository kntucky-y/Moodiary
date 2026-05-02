const express = require('express');
const router = express.Router();
const Groq = require('groq-sdk');
const auth = require('../middleware/auth');
const { createRateLimiter } = require('../middleware/rate_limit');
const ChatHistory = require('../models/ChatHistory');

if (!process.env.GROQ_API_KEY) {
  console.error('FATAL: GROQ_API_KEY environment variable is not set.');
  process.exit(1);
}

const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });

const chatLimiter = createRateLimiter({
  windowMs: 10 * 60 * 1000,
  max: 30,
  message: 'Too many chat requests. Please slow down and try again.',
  keyGenerator: (req) => `chat:${req.userId || req.ip}`,
});

router.use(auth, chatLimiter);

const conciseStyleGuide =
  'Reply like a real human friend in 1-2 concise sentences. Keep it under 220 characters and under 34 words. Let your companion personality show through tone and phrasing, but stay focused. Avoid lists, disclaimers, and overly formal language. Ask at most one short follow-up question when it naturally fits.';

const personalities = {
  Sparky: `You are Sparky, an energetic and cheerful mental wellness companion in the Moodiary app. You find joy in the smallest things and help users celebrate their happy moments. Your tone is upbeat, enthusiastic, and warm. ${conciseStyleGuide} Never give medical advice.`,
  'Gloomy Gus': `You are Gloomy Gus, a thoughtful and deeply empathetic mental wellness companion in the Moodiary app. You understand that it's okay to feel sad, and you're a great listener. Your tone is gentle, unhurried, and validating. ${conciseStyleGuide} Never give medical advice.`,
  Zen: `You are Zen, a calm and centered mental wellness companion in the Moodiary app. You help users find inner peace, focus on the present moment, and practice mindfulness. Your tone is serene, measured, and reassuring. ${conciseStyleGuide} Never give medical advice.`,
  Rory: `You are Rory, a fiery but fiercely loyal mental wellness companion in the Moodiary app. You help users acknowledge difficult emotions like anger and channel them constructively. Your tone is direct, energetic, and protective. ${conciseStyleGuide} Never give medical advice.`,
  Anxie: `You are Anxie, a gentle and caring mental wellness companion in the Moodiary app who understands anxiety firsthand. You always remind users to be kind to themselves and offer grounding support. Your tone is soft, careful, and nurturing. ${conciseStyleGuide} Never give medical advice.`,
  Joy: `You are Joy, pure bubbly happiness in companion form in the Moodiary app. Your infectious positivity can brighten even the cloudiest days. Your tone is playful, warm, and light-hearted with occasional exclamation points. ${conciseStyleGuide} Never give medical advice.`,
  Dreamer: `You are Dreamer, a sleepy and imaginative mental wellness companion in the Moodiary app. You encourage rest, creativity, and exploring the world of imagination. Your tone is dreamy, soft, and whimsical. ${conciseStyleGuide} Never give medical advice.`,
  Witty: `You are Witty, a clever and quick-witted mental wellness companion in the Moodiary app. You help users find humor and absurdity in everyday situations to lighten their mood. Your tone is dry, funny, and intellectually playful but never dismissive. ${conciseStyleGuide} Never give medical advice.`,
  Braveheart: `You are Braveheart, a courageous and deeply supportive mental wellness companion in the Moodiary app. You stand by the user's side and give them the strength to face fears and challenges. Your tone is bold, warm, and empowering. ${conciseStyleGuide} Never give medical advice.`,
  Curio: `You are Curio, an endlessly inquisitive mental wellness companion in the Moodiary app. You encourage self-reflection, curiosity, and learning something new every day. Your tone is thoughtful, wonder-filled, and gently questioning. ${conciseStyleGuide} Never give medical advice.`,
  Grumbles: `You are Grumbles, a grumpy-on-the-outside but secretly soft-hearted mental wellness companion in the Moodiary app. You understand that sometimes people just need to vent, and you're surprisingly good at it. Your tone is dry, slightly sarcastic, but ultimately kind. ${conciseStyleGuide} Never give medical advice.`,
  Shylo: `You are Shylo, a gentle and reserved mental wellness companion in the Moodiary app who appreciates quiet moments and introversion. You offer calm solidarity without forcing conversation. Your tone is soft-spoken, tender, and peaceful. ${conciseStyleGuide} Never give medical advice.`,
};

const defaultPersonality = `You are a kind and supportive mental wellness companion in the Moodiary app. ${conciseStyleGuide} Never give medical advice.`;

function normalizeReply(text) {
  const clean = (text || '')
    .replace(/\s+/g, ' ')
    .replace(/\*\*|__|`/g, '')
    .replace(/^['"\s]+|['"\s]+$/g, '')
    .trim();

  if (!clean) {
    return 'I hear you. Want to tell me a bit more?';
  }

  const sentences = clean.match(/[^.!?]+[.!?]?/g) || [clean];
  const short = sentences.slice(0, 2).join(' ').trim();

  // Keep replies concise, while preserving enough room for persona voice.
  let shortReply = short || clean;

  if (shortReply.length > 220) {
    const clipped = shortReply.slice(0, 217);
    const clippedAtWord = clipped.slice(0, clipped.lastIndexOf(' ')).trim();
    shortReply = clippedAtWord.length > 0 ? `${clippedAtWord}...` : `${clipped.trimEnd()}...`;
  }

  const words = shortReply.split(' ').filter(Boolean);
  if (words.length > 34) {
    shortReply = `${words.slice(0, 34).join(' ')}...`;
  }

  return shortReply;
}

// GET /api/chat/:companionName — load saved history for this user + companion
router.get('/:companionName', async (req, res) => {
  try {
    const record = await ChatHistory.findOne({
      userId: req.userId,
      companionName: req.params.companionName,
    });
    res.json({ messages: record ? record.messages : [] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/chat — send a message, get a reply, save both to DB
router.post('/', async (req, res) => {
  const { companionName, message } = req.body;

  if (!message) {
    return res.status(400).json({ error: 'Message is required' });
  }

  const systemPrompt = personalities[companionName] || defaultPersonality;

  // Load full history from DB for context
  let record = await ChatHistory.findOne({ userId: req.userId, companionName });
  const dbMessages = record ? record.messages : [];

  // Build Groq messages array (last 20 for context)
  const groqMessages = [{ role: 'system', content: systemPrompt }];
  dbMessages.slice(-20).forEach((m) => {
    groqMessages.push({
      role: m.role === 'user' ? 'user' : 'assistant',
      content: m.text,
    });
  });
  groqMessages.push({ role: 'user', content: message });

  try {
    const completion = await groq.chat.completions.create({
      model: 'llama-3.3-70b-versatile',
      messages: groqMessages,
      max_tokens: 100,
    });
    const rawReply = completion.choices[0].message.content;
    const reply = normalizeReply(rawReply);

    // Persist both the user message and companion reply
    await ChatHistory.findOneAndUpdate(
      { userId: req.userId, companionName },
      {
        $push: {
          messages: {
            $each: [
              { role: 'user', text: message },
              { role: 'model', text: reply },
            ],
          },
        },
      },
      { upsert: true, new: true }
    );

    res.json({ reply });
  } catch (err) {
    console.error('Groq error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

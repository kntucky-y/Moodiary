// MBTI-style scoring utility.
// Reference notes and citation trail are documented in:
// moodiary/docs/mbti_methodology.md
// This implementation is an educational, app-specific assessment and not the
// official licensed MBTI instrument.

const MBTI_QUESTION_COUNT = 30;

const MBTI_QUESTIONS = [
  { id: 1, dimension: 'EI', reverse: false, text: 'I feel energized after spending time with many people.' },
  { id: 2, dimension: 'EI', reverse: true, text: 'I prefer to process my thoughts alone before speaking.' },
  { id: 3, dimension: 'EI', reverse: false, text: 'I usually start conversations in group settings.' },
  { id: 4, dimension: 'EI', reverse: true, text: 'Quiet time is essential for me after social events.' },
  { id: 5, dimension: 'EI', reverse: false, text: 'I think better by talking ideas out loud.' },
  { id: 6, dimension: 'EI', reverse: true, text: 'I often keep my reactions private at first.' },
  { id: 7, dimension: 'EI', reverse: false, text: 'I enjoy meeting new people more than revisiting familiar plans.' },
  { id: 8, dimension: 'EI', reverse: true, text: 'I prefer deep one-on-one talks over lively group conversations.' },

  { id: 9, dimension: 'SN', reverse: false, text: 'I trust concrete facts more than hunches.' },
  { id: 10, dimension: 'SN', reverse: true, text: 'I enjoy imagining future possibilities beyond present reality.' },
  { id: 11, dimension: 'SN', reverse: false, text: 'I focus on what is practical right now.' },
  { id: 12, dimension: 'SN', reverse: true, text: 'I often notice hidden patterns and meanings.' },
  { id: 13, dimension: 'SN', reverse: false, text: 'I prefer clear instructions over open-ended exploration.' },
  { id: 14, dimension: 'SN', reverse: true, text: 'I am drawn to ideas that challenge conventional thinking.' },
  { id: 15, dimension: 'SN', reverse: false, text: 'I remember details of past experiences easily.' },
  { id: 16, dimension: 'SN', reverse: true, text: 'I naturally connect separate ideas into a bigger picture.' },

  { id: 17, dimension: 'TF', reverse: false, text: 'I make decisions by weighing objective logic first.' },
  { id: 18, dimension: 'TF', reverse: true, text: 'I consider personal values before making final decisions.' },
  { id: 19, dimension: 'TF', reverse: false, text: 'I can separate criticism of ideas from criticism of people.' },
  { id: 20, dimension: 'TF', reverse: true, text: 'I avoid choices that may hurt relationships unnecessarily.' },
  { id: 21, dimension: 'TF', reverse: false, text: 'I prefer clear criteria over emotional impressions.' },
  { id: 22, dimension: 'TF', reverse: true, text: 'I value empathy as much as accuracy in tough conversations.' },
  { id: 23, dimension: 'TF', reverse: false, text: 'I prioritize fairness through consistent rules.' },

  { id: 24, dimension: 'JP', reverse: false, text: 'I prefer planning ahead instead of improvising at the last minute.' },
  { id: 25, dimension: 'JP', reverse: true, text: 'I like keeping options open until the final moment.' },
  { id: 26, dimension: 'JP', reverse: false, text: 'I feel better once decisions are settled.' },
  { id: 27, dimension: 'JP', reverse: true, text: 'I enjoy adapting as new information appears.' },
  { id: 28, dimension: 'JP', reverse: false, text: 'I usually create structure before starting a task.' },
  { id: 29, dimension: 'JP', reverse: true, text: 'I work best in flexible environments with minimal constraints.' },
  { id: 30, dimension: 'JP', reverse: false, text: 'I keep to-do lists and schedules consistently.' },
];

const COMPANION_BY_ID = {
  1: {
    id: 1,
    name: 'Sparky',
    description: 'An energetic and cheerful friend who helps you celebrate small wins.',
  },
  2: {
    id: 2,
    name: 'Gloomy Gus',
    description: 'A thoughtful listener who validates heavy emotions with empathy.',
  },
  3: {
    id: 3,
    name: 'Zen',
    description: 'A calm, grounding companion focused on clarity and presence.',
  },
  4: {
    id: 4,
    name: 'Rory',
    description: 'A protective and fiery supporter who channels strong emotions productively.',
  },
  5: {
    id: 5,
    name: 'Anxie',
    description: 'A gentle worrier who helps you handle uncertainty with care.',
  },
  6: {
    id: 6,
    name: 'Joy',
    description: 'A bubbly mood-lifter with contagious optimism.',
  },
  7: {
    id: 7,
    name: 'Dreamer',
    description: 'An imaginative companion who supports reflection and rest.',
  },
  8: {
    id: 8,
    name: 'Witty',
    description: 'A clever guide that uses humor and perspective shifts.',
  },
  9: {
    id: 9,
    name: 'Braveheart',
    description: 'A courageous ally that encourages action despite fear.',
  },
  10: {
    id: 10,
    name: 'Curio',
    description: 'A curious explorer who helps you learn and experiment.',
  },
  11: {
    id: 11,
    name: 'Grumbles',
    description: 'A grumpy-softie who gives space to vent and recover.',
  },
  12: {
    id: 12,
    name: 'Shylo',
    description: 'A reserved friend who values quiet support and gentle pacing.',
  },
};

const MBTI_TO_COMPANIONS = {
  ISTJ: [3, 9, 12],
  ISFJ: [12, 2, 3],
  INFJ: [3, 7, 12],
  INTJ: [3, 10, 8],
  ISTP: [9, 10, 11],
  ISFP: [7, 12, 6],
  INFP: [7, 2, 12],
  INTP: [10, 8, 3],
  ESTP: [1, 9, 8],
  ESFP: [6, 1, 8],
  ENFP: [6, 7, 10],
  ENTP: [8, 10, 1],
  ESTJ: [9, 1, 3],
  ESFJ: [6, 2, 1],
  ENFJ: [6, 9, 3],
  ENTJ: [9, 10, 1],
};

const validateAnswers = (answers) => {
  if (!Array.isArray(answers) || answers.length !== MBTI_QUESTION_COUNT) {
    return 'Answers must contain exactly 30 items';
  }
  const invalid = answers.some((value) => !Number.isInteger(value) || value < 1 || value > 5);
  if (invalid) {
    return 'Each answer must be an integer from 1 to 5';
  }
  return null;
};

const scoreMbti = (answers) => {
  const validationError = validateAnswers(answers);
  if (validationError) {
    return { error: validationError };
  }

  const scores = { E: 0, I: 0, S: 0, N: 0, T: 0, F: 0, J: 0, P: 0 };

  for (let i = 0; i < MBTI_QUESTIONS.length; i += 1) {
    const question = MBTI_QUESTIONS[i];
    const answer = answers[i];
    const normalized = question.reverse ? 6 - answer : answer;

    if (question.dimension === 'EI') {
      scores.E += normalized;
      scores.I += 6 - normalized;
    } else if (question.dimension === 'SN') {
      scores.S += normalized;
      scores.N += 6 - normalized;
    } else if (question.dimension === 'TF') {
      scores.T += normalized;
      scores.F += 6 - normalized;
    } else if (question.dimension === 'JP') {
      scores.J += normalized;
      scores.P += 6 - normalized;
    }
  }

  const type = `${scores.E >= scores.I ? 'E' : 'I'}${scores.S >= scores.N ? 'S' : 'N'}${scores.T >= scores.F ? 'T' : 'F'}${scores.J >= scores.P ? 'J' : 'P'}`;

  const suggestedCompanionIds = MBTI_TO_COMPANIONS[type] || [3, 6, 12];
  const suggestedCompanions = suggestedCompanionIds
    .map((id) => COMPANION_BY_ID[id])
    .filter(Boolean);

  return {
    type,
    scores,
    suggestedCompanionIds,
    suggestedCompanions,
  };
};

module.exports = {
  MBTI_QUESTION_COUNT,
  MBTI_QUESTIONS,
  scoreMbti,
};

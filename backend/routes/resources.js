const express = require('express');
const router = express.Router();

// GET /api/resources - Get curated mental health resources
router.get('/', async (req, res) => {
  try {
    const resources = [
      {
        id: '1',
        title: 'Understanding Anxiety',
        description:
          'A comprehensive guide to recognizing and managing anxiety symptoms in daily life.',
        category: 'Mental Health',
        url: 'https://www.mayoclinic.org/diseases-conditions/anxiety-disorders/symptoms-causes/syc-20350961',
        icon: 'anxiety',
        featured: true,
      },
      {
        id: '2',
        title: 'Meditation Basics',
        description:
          'Learn foundational meditation techniques to reduce stress and improve focus.',
        category: 'Mindfulness',
        url: 'https://www.headspace.com/work/meditation-for-beginners',
        icon: 'meditation',
        featured: true,
      },
      {
        id: '3',
        title: 'Sleep Hygiene Tips',
        description:
          'Improve your sleep quality with proven sleep hygiene practices and bedtime routines.',
        category: 'Wellness',
        url: 'https://www.sleepfoundation.org/sleep-hygiene',
        icon: 'sleep',
        featured: true,
      },
      {
        id: '4',
        title: 'Coping with Depression',
        description:
          'Strategies and techniques to manage depression symptoms and improve mental health.',
        category: 'Mental Health',
        url: 'https://www.samhsa.gov/find-help/national-helpline',
        icon: 'depression',
        featured: false,
      },
      {
        id: '5',
        title: 'Breathing Exercises',
        description:
          'Step-by-step breathing techniques to calm your mind and reduce racing thoughts.',
        category: 'Mindfulness',
        url: 'https://www.verywellmind.com/breathing-exercises-for-anxiety-3144786',
        icon: 'breathing',
        featured: false,
      },
      {
        id: '6',
        title: 'Exercise and Mental Health',
        description:
          'How regular physical activity can significantly improve your mental well-being.',
        category: 'Wellness',
        url: 'https://www.mentalhealth.org/our-work/mental-health-movement/exercise',
        icon: 'exercise',
        featured: false,
      },
      {
        id: '7',
        title: 'Nutrition for Mood',
        description:
          'Discover foods and nutrients that support emotional health and brain function.',
        category: 'Wellness',
        url: 'https://www.psychiatry.org/patients-families/what-is-mental-illness/eating-disorders-and-mental-health',
        icon: 'nutrition',
        featured: false,
      },
      {
        id: '8',
        title: 'Social Connection Matters',
        description:
          'The importance of maintaining healthy relationships and social bonds for mental health.',
        category: 'Social',
        url: 'https://www.apa.org/science/about/psa/social-connection',
        icon: 'social',
        featured: false,
      },
    ];

    // Optional: filter by category if provided
    const { category } = req.query;
    const filtered = category
      ? resources.filter((r) => r.category.toLowerCase() === category.toLowerCase())
      : resources;

    res.json({ resources: filtered, total: filtered.length });
  } catch (err) {
    console.error('Get resources error', err);
    res.status(500).json({ error: 'Unable to fetch resources' });
  }
});

// GET /api/resources/categories - Get available resource categories
router.get('/categories/list', async (req, res) => {
  try {
    const categories = [
      'Mental Health',
      'Mindfulness',
      'Wellness',
      'Social',
    ];
    res.json({ categories });
  } catch (err) {
    console.error('Get categories error', err);
    res.status(500).json({ error: 'Unable to fetch categories' });
  }
});

module.exports = router;

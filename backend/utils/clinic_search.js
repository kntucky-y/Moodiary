const OVERPASS_URLS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.nchc.org.tw/api/interpreter',
];
const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';
const CACHE_TTL_MS = 5 * 60 * 1000;

const cache = new Map();

function toNumber(value) {
  const num = Number(value);
  return Number.isFinite(num) ? num : null;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function normalizeText(value) {
  return value ? String(value).trim().toLowerCase() : '';
}

function haversineMeters(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const earthRadius = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 2 * earthRadius * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function cacheKey(lat, lng, radius, limit) {
  return [lat.toFixed(3), lng.toFixed(3), radius, limit].join(':');
}

function getCenter(element) {
  if (typeof element.lat === 'number' && typeof element.lon === 'number') {
    return { lat: element.lat, lng: element.lon };
  }
  if (
    element.center &&
    typeof element.center.lat === 'number' &&
    typeof element.center.lon === 'number'
  ) {
    return { lat: element.center.lat, lng: element.center.lon };
  }
  return null;
}

function getAddress(tags) {
  const pieces = [
    tags['addr:housenumber'],
    tags['addr:street'],
    tags['addr:suburb'],
    tags['addr:city'],
    tags['addr:state'],
    tags['addr:country'],
  ]
    .map((item) => (item ? String(item).trim() : ''))
    .filter((item) => item.length > 0);
  return pieces.join(', ');
}

function isRelevantClinic(tags) {
  const haystack = [
    tags.name,
    tags.brand,
    tags.operator,
    tags.amenity,
    tags.healthcare,
    tags['healthcare:speciality'],
    tags.description,
    tags.note,
    tags.website,
  ]
    .map(normalizeText)
    .join(' ');

  const keywords = [
    'mental health',
    'psychi',
    'psycholog',
    'psychother',
    'counsel',
    'therapy',
    'behavioral health',
    'behavioural health',
    'wellness center',
    'wellness centre',
    'behavioral medicine',
    'addiction',
    'therapy clinic',
  ];

  return keywords.some((keyword) => haystack.includes(keyword));
}

function normalizeOverpassElement(element, lat, lng) {
  const tags = element.tags || {};
  const center = getCenter(element);
  if (!center) {
    return null;
  }

  const distanceMeters = haversineMeters(lat, lng, center.lat, center.lng);
  const title = tags.name || tags.operator || 'Mental health clinic';
  const specialty = tags['healthcare:speciality'] || tags.healthcare || tags.amenity || '';
  const address = getAddress(tags);

  return {
    id: `osm:${element.type}:${element.id}`,
    name: title,
    description:
      tags.description ||
      specialty ||
      'Nearby mental health service and support provider.',
    address: address || tags['addr:full'] || '',
    phone: tags.phone || tags['contact:phone'] || '',
    website: tags.website || tags['contact:website'] || '',
    openingHours: tags.opening_hours || '',
    latitude: center.lat,
    longitude: center.lng,
    distanceMeters,
    source: 'openstreetmap',
    tags: {
      amenity: tags.amenity || '',
      healthcare: tags.healthcare || '',
      speciality: tags['healthcare:speciality'] || '',
      operator: tags.operator || '',
      wheelchair: tags.wheelchair || '',
    },
    relevance: isRelevantClinic(tags) ? 'high' : 'medium',
  };
}

function dedupeClinics(clinics) {
  const seen = new Set();
  const unique = [];

  for (const clinic of clinics) {
    const key = [
      normalizeText(clinic.name),
      clinic.address,
      clinic.latitude.toFixed(5),
      clinic.longitude.toFixed(5),
    ].join('|');

    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(clinic);
  }

  return unique;
}

async function fetchJson(
  url,
  { body, method = 'GET', headers = {}, timeoutMs = 15000 } = {},
) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const requestHeaders = {
    'User-Agent': 'Moodiary/1.0 (clinic search)',
    ...headers,
  };

  try {
    const response = await fetch(url, {
      method,
      headers: requestHeaders,
      body,
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`Request failed with ${response.status}`);
    }
    return response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function queryOverpassNearbyClinics(lat, lng, radius) {
  const query = `
    [out:json][timeout:20];
    (
      node(around:${radius},${lat},${lng})["healthcare"];
      way(around:${radius},${lat},${lng})["healthcare"];
      relation(around:${radius},${lat},${lng})["healthcare"];
      node(around:${radius},${lat},${lng})["amenity"~"clinic|hospital|doctors",i];
      way(around:${radius},${lat},${lng})["amenity"~"clinic|hospital|doctors",i];
      relation(around:${radius},${lat},${lng})["amenity"~"clinic|hospital|doctors",i];
    );
    out center tags;
  `;

  let payload;
  let lastError;
  for (const url of OVERPASS_URLS) {
    try {
      payload = await fetchJson(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `data=${encodeURIComponent(query)}`,
        timeoutMs: 20000,
      });
      break;
    } catch (error) {
      lastError = error;
    }
  }

  if (!payload && lastError) {
    throw lastError;
  }

  const elements = payload && Array.isArray(payload.elements) ? payload.elements : [];
  const clinics = elements
    .map((element) => normalizeOverpassElement(element, lat, lng))
    .filter(Boolean)
    .filter((clinic) => clinic.relevance === 'high')
    .sort((a, b) => a.distanceMeters - b.distanceMeters);

  return dedupeClinics(clinics);
}

async function queryNominatimFallback(lat, lng, radius, limit) {
  const viewbox = [
    lng - radius / 111000,
    lat + radius / 111000,
    lng + radius / 111000,
    lat - radius / 111000,
  ].join(',');

  const queries = [
    'mental health clinic',
    'psychiatrist',
    'psychologist',
    'therapy center',
    'counselling center',
  ];

  const results = [];
  for (const query of queries) {
    const url = new URL(NOMINATIM_URL);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('limit', String(limit));
    url.searchParams.set('bounded', '1');
    url.searchParams.set('viewbox', viewbox);
    url.searchParams.set('q', query);

    const payload = await fetchJson(url.toString(), {
      headers: {
        'User-Agent': 'Moodiary/1.0 (mental health resource map)',
      },
      timeoutMs: 15000,
    });

    if (!Array.isArray(payload)) continue;

    for (const item of payload) {
      const itemLat = toNumber(item.lat);
      const itemLng = toNumber(item.lon);
      if (itemLat == null || itemLng == null) continue;

      const distanceMeters = haversineMeters(lat, lng, itemLat, itemLng);
      results.push({
        id: `nominatim:${item.place_id}`,
        name: item.display_name?.split(',')?.[0]?.trim() || item.name || query,
        description: item.type || item.class || 'Mental health service nearby.',
        address: item.display_name || '',
        phone: '',
        website: '',
        openingHours: '',
        latitude: itemLat,
        longitude: itemLng,
        distanceMeters,
        source: 'nominatim',
        tags: { query },
        relevance: 'fallback',
      });
    }
  }

  return dedupeClinics(results)
    .sort((a, b) => a.distanceMeters - b.distanceMeters)
    .slice(0, limit);
}

async function getNearbyMentalHealthClinics({ lat, lng, radius = 5000, limit = 25 }) {
  const normalizedLat = toNumber(lat);
  const normalizedLng = toNumber(lng);

  if (normalizedLat == null || normalizedLng == null) {
    throw new Error('Invalid coordinates');
  }

  const safeRadius = clamp(Number(radius) || 5000, 1000, 25000);
  const safeLimit = clamp(Number(limit) || 25, 1, 50);
  const key = cacheKey(normalizedLat, normalizedLng, safeRadius, safeLimit);
  const cached = cache.get(key);

  if (cached && cached.expiresAt > Date.now()) {
    return cached.data;
  }

  let clinics = [];
  let overpassError = null;
  try {
    clinics = await queryOverpassNearbyClinics(normalizedLat, normalizedLng, safeRadius);
  } catch (error) {
    overpassError = error;
  }

  if (!clinics.length) {
    try {
      clinics = await queryNominatimFallback(
        normalizedLat,
        normalizedLng,
        safeRadius,
        safeLimit,
      );
    } catch (error) {
      console.warn('Nominatim clinic fallback failed:', error.message);
    }
  }

  if (!clinics.length && overpassError) {
    console.warn('Overpass clinic lookup failed:', overpassError.message);
  }

  const data = {
    clinics: clinics.slice(0, safeLimit),
    center: {
      lat: normalizedLat,
      lng: normalizedLng,
    },
    radiusMeters: safeRadius,
    total: clinics.length,
    source: clinics.length ? clinics[0].source : 'none',
  };

  cache.set(key, {
    expiresAt: Date.now() + CACHE_TTL_MS,
    data,
  });

  return data;
}

module.exports = {
  getNearbyMentalHealthClinics,
};
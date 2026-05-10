const http = require('http');
const https = require('https');
const OVERPASS_URLS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.nchc.org.tw/api/interpreter',
];
const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';
const CACHE_TTL_MS = 5 * 60 * 1000;
const OVERPASS_TIMEOUT_MS = 9000;
const NOMINATIM_TIMEOUT_MS = 4500;
const NOMINATIM_EMAIL = (process.env.NOMINATIM_EMAIL || '').trim();
const OVERPASS_QUERY_TIMEOUT_S = 10;
const RESPONSE_BUDGET_MS = 10000;

const cache = new Map();
let overpassFailureCount = 0;
let overpassDisabledUntil = 0;
const OVERPASS_BACKOFF_BASE_MS = 2 * 60 * 1000;
const OVERPASS_BACKOFF_MAX_MS = 10 * 60 * 1000;

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
    relevance: 'unfiltered',
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
  const requestHeaders = {
    'User-Agent': NOMINATIM_EMAIL
      ? `Moodiary/1.0 (clinic search; ${NOMINATIM_EMAIL})`
      : 'Moodiary/1.0 (clinic search)',
    ...headers,
  };

  if (typeof fetch === 'function') {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
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

  return new Promise((resolve, reject) => {
    let parsedUrl;
    try {
      parsedUrl = new URL(url);
    } catch (_) {
      reject(new Error('Invalid request URL'));
      return;
    }

    const transport = parsedUrl.protocol === 'https:' ? https : http;
    const req = transport.request(
      parsedUrl,
      {
        method,
        headers: requestHeaders,
      },
      (res) => {
        let raw = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          raw += chunk;
        });
        res.on('end', () => {
          if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
            reject(new Error(`Request failed with ${res.statusCode || 0}`));
            return;
          }
          try {
            resolve(raw ? JSON.parse(raw) : {});
          } catch (_) {
            reject(new Error('Invalid JSON response'));
          }
        });
      },
    );

    req.on('error', reject);
    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error('Request timed out'));
    });

    if (body) {
      req.write(body);
    }
    req.end();
  });
}

async function firstSuccessfulJson(urls, requestFactory) {
  const errors = [];
  for (const url of urls) {
    try {
      return await requestFactory(url);
    } catch (error) {
      errors.push(error);
    }
  }
  throw errors[0] || new Error('All providers failed');
}

async function queryOverpassNearbyClinics(lat, lng, radius) {
  if (Date.now() < overpassDisabledUntil) {
    const error = new Error('Overpass temporarily disabled due to failures');
    error.code = 'OVERPASS_BACKOFF';
    throw error;
  }
  const query = `
    [out:json][timeout:${OVERPASS_QUERY_TIMEOUT_S}];
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
  try {
    payload = await firstSuccessfulJson(OVERPASS_URLS, (url) =>
      fetchJson(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `data=${encodeURIComponent(query)}`,
        timeoutMs: OVERPASS_TIMEOUT_MS,
      }),
    );
  } catch (error) {
    const firstError = error;
    overpassFailureCount += 1;
    const backoffMs = Math.min(
      OVERPASS_BACKOFF_MAX_MS,
      OVERPASS_BACKOFF_BASE_MS * overpassFailureCount,
    );
    overpassDisabledUntil = Date.now() + backoffMs;
    throw firstError;
  }

  const elements = payload && Array.isArray(payload.elements) ? payload.elements : [];
  const clinics = elements
    .map((element) => normalizeOverpassElement(element, lat, lng))
    .filter((clinic) => clinic && clinic.distanceMeters <= radius)
    .sort((a, b) => a.distanceMeters - b.distanceMeters);

  overpassFailureCount = 0;
  overpassDisabledUntil = 0;
  return dedupeClinics(clinics);
}

async function queryNominatimFallback(lat, lng, radius, limit) {
  const latAdjust = radius / 111000;
  const cosLat = Math.cos((lat * Math.PI) / 180);
  const lngAdjust = cosLat > 0.01 ? radius / (111000 * cosLat) : latAdjust;
  const viewbox = [
    lng - lngAdjust,
    lat + latAdjust,
    lng + lngAdjust,
    lat - latAdjust,
  ].join(',');

  const queries = ['mental health clinic', 'psychiatrist', 'psychologist'];

  const results = [];
  for (const query of queries) {
    const url = new URL(NOMINATIM_URL);
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('limit', String(Math.min(limit, 10)));
    url.searchParams.set('bounded', '1');
    url.searchParams.set('viewbox', viewbox);
    url.searchParams.set('q', query);
    if (NOMINATIM_EMAIL) {
      url.searchParams.set('email', NOMINATIM_EMAIL);
    }

    const payload = await fetchJson(url.toString(), {
      headers: {
        'User-Agent': NOMINATIM_EMAIL
          ? `Moodiary/1.0 (mental health resource map; ${NOMINATIM_EMAIL})`
          : 'Moodiary/1.0 (mental health resource map)',
      },
      timeoutMs: NOMINATIM_TIMEOUT_MS,
    });

    if (!Array.isArray(payload)) continue;

    for (const item of payload) {
      const itemLat = toNumber(item.lat);
      const itemLng = toNumber(item.lon);
      if (itemLat == null || itemLng == null) continue;

      const distanceMeters = haversineMeters(lat, lng, itemLat, itemLng);
      if (distanceMeters > radius * 1.05) continue;
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

    if (results.length >= limit) {
      break;
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

  const deadline = Date.now() + RESPONSE_BUDGET_MS;
  const remainingBudgetMs = () => Math.max(0, deadline - Date.now());

  let clinics = [];
  let overpassError = null;
  let nominatimError = null;

  const overpassPromise = queryOverpassNearbyClinics(
    normalizedLat,
    normalizedLng,
    safeRadius,
  )
    .then((data) => ({ source: 'overpass', data }))
    .catch((error) => ({ source: 'overpass', data: [], error }));

  const nominatimPromise = queryNominatimFallback(
    normalizedLat,
    normalizedLng,
    safeRadius,
    safeLimit,
  )
    .then((data) => ({ source: 'nominatim', data }))
    .catch((error) => ({ source: 'nominatim', data: [], error }));

  const settled = await Promise.race([
    Promise.allSettled([overpassPromise, nominatimPromise]),
    new Promise((resolve) =>
      setTimeout(() => resolve('budget'), remainingBudgetMs()),
    ),
  ]);

  if (settled === 'budget') {
    console.warn('Nearby clinics request exceeded response budget (first race).');
    return {
      clinics: [],
      center: { lat: normalizedLat, lng: normalizedLng },
      radiusMeters: safeRadius,
      total: 0,
      source: 'none',
    };
  }

  const [overpassSettled, nominatimSettled] = settled;
  const overpassResult = overpassSettled.status === 'fulfilled'
    ? overpassSettled.value
    : { source: 'overpass', data: [], error: overpassSettled.reason };
  const nominatimResult = nominatimSettled.status === 'fulfilled'
    ? nominatimSettled.value
    : { source: 'nominatim', data: [], error: nominatimSettled.reason };

  clinics = overpassResult.data?.length
    ? overpassResult.data
    : (nominatimResult.data || []);
  overpassError = overpassResult.error || null;
  nominatimError = nominatimResult.error || null;

  if (!clinics.length) {
    if (overpassError) {
      console.warn('Overpass clinic lookup failed:', overpassError.message);
    }
    if (nominatimError) {
      console.warn('Nominatim clinic fallback failed:', nominatimError.message);
    }
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

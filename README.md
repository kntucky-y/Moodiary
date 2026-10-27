# Moodiary

Moodiary is a full-stack journaling and mood-tracking platform with a Flutter client and a Node/Express backend. It supports secure authentication, password recovery, mood insights, and social features such as chat, forums, and notifications.

## Features

- Mood logging, trends, and insights
- Guided journaling with tags
- MBTI-style companion matching (educational, non-clinical)
- Friends chat with realtime messaging and notifications
- Community forums
- Resources map powered by OpenStreetMap
- Optional AI mood coach tasks and summaries

## Tech stack

- Flutter (mobile, web, desktop)
- Node.js + Express API
- MongoDB + Mongoose
- Socket.io realtime messaging
- Firebase Admin for push notifications
- Groq SDK for AI-assisted content

## Repository layout

- backend/ - Node/Express API, sockets, and data models
- moodiary/ - Flutter application
- moodiary/docs/ - Product and methodology notes

## Getting started

### Prerequisites

- Node.js 18+
- Flutter SDK (Dart 3.11+)
- MongoDB instance (local or Atlas)

### Backend setup

1. Install dependencies:

```
cd backend
npm install
```

2. Create backend/.env with your runtime values:

```
MONGO_URI=mongodb+srv://<user>:<pass>@cluster.example.mongodb.net/moodiary
JWT_SECRET=replace_with_a_strong_secret
PORT=5000

# Optional: AI insights
GROQ_API_KEY=your_groq_api_key
GROQ_MODEL=llama-3.3-70b-versatile

# Optional: Email (SMTP)
MAIL_SERVICE=gmail
MAIL_USER=you@example.com
MAIL_PASS=your_app_password
MAIL_FROM="Moodiary <no-reply@yourdomain.com>"

# Optional: Email (custom SMTP)
MAIL_HOST=smtp.mailgun.org
MAIL_PORT=587
MAIL_SECURE=false

# Optional: Email via Resend API (SMTP-free)
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx

# Optional: Push notifications (Firebase Admin)
FIREBASE_SERVICE_ACCOUNT_JSON={...}
```

3. Start the server:

```
npm run dev
```

Health check:

```
GET /api/health
```

### Flutter app setup

1. Install dependencies:

```
cd moodiary
flutter pub get
```

2. Run the app with a backend URL:

```
flutter run --dart-define=BACKEND_BASE_URL=http://localhost:5000
```

For production builds, set the backend URL at build time:

```
flutter build apk --dart-define=BACKEND_BASE_URL=https://api.your-domain.com
```

## Security and sensitive data

- Do not commit secrets, API keys, passwords, or tokens.
- Keep backend/.env out of version control.
- Rotate credentials that were ever committed to git history.
- Avoid embedding credentials in Flutter source; use --dart-define for non-secret runtime settings only.

## Notes

- MBTI methodology details live in moodiary/docs/mbti_methodology.md.
- This app is not a clinical diagnostic tool.

## License

All rights reserved. See LICENSE for details.

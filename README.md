<div align="center">

# Moodiary

### A private space to understand your moods, write honestly, and stay connected.

<p>
  <a href="https://github.com/kntucky-y/Moodiary"><img src="https://img.shields.io/badge/Repository-181717?style=for-the-badge&logo=github&logoColor=white" alt="Repository" /></a>
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white" alt="Node.js" />
  <img src="https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white" alt="MongoDB" />
</p>

<img src="https://raw.githubusercontent.com/kntucky-y/Moodiary/main/moodiary/assets/moodiary.png" width="180" alt="Moodiary app artwork" />

</div>

## Overview

Moodiary is a full-stack journaling and mood-tracking platform designed to
make reflection feel approachable. The Flutter client runs across mobile, web,
and desktop, while a Node/Express API handles authentication, journaling,
insights, social features, and notifications.

> Moodiary is an educational and wellness tool, not a clinical diagnostic
> service.

## Features

- **Mood logging** with trends, insights, expressive mood assets, and tags
- **Guided journaling** for structured reflection and personal notes
- **AI-assisted summaries** and mood-coach tasks through Groq
- **Companion matching** based on an MBTI-style educational flow
- **Friends chat** with realtime messaging, friend requests, and notifications
- **Community forums** for sharing and discussion
- **Resources map** powered by OpenStreetMap
- **Password recovery**, email delivery, and Firebase push notifications

## Visual assets

<p align="center">
  <img src="https://raw.githubusercontent.com/kntucky-y/Moodiary/main/moodiary/assets/very-happy.png" width="110" alt="Very happy mood" />
  <img src="https://raw.githubusercontent.com/kntucky-y/Moodiary/main/moodiary/assets/meditation.png" width="110" alt="Meditation mood illustration" />
  <img src="https://raw.githubusercontent.com/kntucky-y/Moodiary/main/moodiary/assets/worried.png" width="110" alt="Worried mood" />
  <img src="https://raw.githubusercontent.com/kntucky-y/Moodiary/main/moodiary/assets/love.png" width="110" alt="Love mood" />
</p>

The app's expressive visual language uses illustrated mood states, guided
activities, and small moments of feedback instead of treating journaling like
a spreadsheet.

## Architecture

```text
Flutter client
  ├─ mobile / web / desktop UI
  ├─ journal and mood flows
  └─ realtime chat and notifications
          │
          ▼
Node.js + Express API
  ├─ JWT authentication and password recovery
  ├─ journal, mood, forum, and friendship services
  ├─ Socket.io realtime messaging
  └─ Firebase / email / Groq integrations
          │
          ▼
MongoDB + Mongoose
```

## Tech stack

- **Client:** Flutter, Dart
- **Backend:** Node.js, Express
- **Database:** MongoDB, Mongoose
- **Realtime:** Socket.io
- **Notifications:** Firebase Admin SDK and Firebase Cloud Messaging
- **AI:** Groq SDK
- **Maps:** OpenStreetMap
- **Email:** SMTP and Resend API

## Repository layout

```text
backend/             Node/Express API, sockets, and data models
moodiary/             Flutter application
moodiary/docs/        Product and methodology notes
```

## Getting started

### Prerequisites

- Node.js 18+
- Flutter SDK with Dart 3.11+
- MongoDB locally or through Atlas

### Backend

```bash
cd backend
npm install
```

Create `backend/.env` with the values required for your environment, then
start the API:

```bash
npm run dev
```

The health endpoint is available at `GET /api/health`.

### Flutter client

```bash
cd moodiary
flutter pub get
flutter run --dart-define=BACKEND_BASE_URL=http://localhost:5000
```

For a production build:

```bash
flutter build apk --dart-define=BACKEND_BASE_URL=https://api.your-domain.com
```

## Security

Never commit `.env` files, API keys, service-account credentials, passwords, or
tokens. Use `--dart-define` for non-secret runtime configuration and rotate
credentials that may have appeared in Git history.

## Documentation and license

- [MBTI methodology](moodiary/docs/mbti_methodology.md)
- [License](LICENSE)

All rights reserved. This project is not licensed for copying, redistribution,
or derivative use.

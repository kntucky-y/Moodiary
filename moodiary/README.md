# Moodiary

Flutter + Node/Express stack for journaling, moods, and social chat. This fork now supports password recovery in addition to the existing email/password flow.

## Backend configuration

Create `backend/.env` with the existing values plus the following additions:

```
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USER=your-user
MAIL_PASS=your-pass
MAIL_FROM="Moodiary <no-reply@moodiary.app>"
PASSWORD_RESET_URL=https://your-app/reset-password
```

The password reset endpoint hashes every token before persisting it. Emails are queued via Nodemailer; if mail creds are missing the server logs the reset link so you can test locally.

## Mobile configuration

No native configuration is required beyond the default Flutter setup. After updating dependencies run:

```
cd moodiary
flutter clean
flutter pub get
flutter run
```

## Auth flows

- **Forgot password** – tap “Forgot password?” on the login screen to send yourself a reset link. Use the new in-app reset screen to paste the token and choose a new password.
- **Email + password login** – the default login/registration fields remain the single source of truth for authentication now that social providers have been removed.

For questions or troubleshooting, see the inline comments in `backend/routes/auth.js` and `lib/screens/auth/login_screen.dart` for the specific data flows.

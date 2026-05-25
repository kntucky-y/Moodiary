# Moodiary

Flutter + Node/Express stack for journaling, moods, and social chat. This fork supports password recovery in addition to the existing email/password flow.

## Repo layout

- `backend/` Node/Express API and realtime socket server
- `moodiary/` Flutter app (Android/iOS/Web/Desktop)

## Backend configuration

Create `backend/.env` with your runtime values. Do not commit real credentials.

```
# SMTP (example values)
MAIL_HOST=smtp.mailgun.org
MAIL_PORT=587
MAIL_SECURE=false
MAIL_USER=postmaster@mg.yourdomain.com
MAIL_PASS=your-smtp-password
MAIL_FROM="Moodiary <no-reply@yourdomain.com>"

# Optional SMTP-free email delivery
# RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx
```

Password reset codes are hashed before storage. Email delivery uses one of these providers:
- `RESEND_API_KEY` set: Resend HTTPS API (no SMTP ports).
- Otherwise: Nodemailer SMTP (Mailgun or another provider).

The reset email contains only a 6-digit verification code. The user enters their email, the code, and a new password in the app.

## Mobile configuration

### Backend URL

The Flutter app reads the backend URL from `BACKEND_BASE_URL` at build time. Example:

```
flutter build apk --dart-define=BACKEND_BASE_URL=https://api.your-domain.com
```

The Resources tab map uses OpenStreetMap and does not require Google Maps API keys or billing setup.

After updating dependencies:

```
cd moodiary
flutter clean
flutter pub get
flutter run
```

## Auth flows

- **Forgot password**: tap “Forgot password?” on the login screen, enter your email, then use the 6-digit code from the email on the reset screen to choose a new password.
- **Email + password login**: the default login/registration fields remain the single source of truth for authentication now that social providers have been removed.

For questions or troubleshooting, see the inline comments in `backend/routes/auth.js` and `lib/screens/auth/login_screen.dart` for the specific data flows.

## Security and sensitive data

- Never commit secrets, API keys, passwords, or tokens.
- Store backend secrets in `backend/.env` and keep it out of version control.
- Avoid hardcoding credentials in Flutter source; use `--dart-define` for non-secret runtime settings only.
- Rotate any credentials that were ever committed to git history.

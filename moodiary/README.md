# Moodiary

Flutter + Node/Express stack for journaling, moods, and social chat. This fork now supports password recovery in addition to the existing email/password flow.

## Backend configuration

Create `backend/.env` with the existing values plus the following additions:

```
# Recommended for a dedicated Gmail sender account
MAIL_SERVICE=gmail
MAIL_USER=your-app-account@gmail.com
MAIL_PASS=your-gmail-app-password
MAIL_FROM="Moodiary <your-app-account@gmail.com>"

# Optional custom SMTP settings instead of MAIL_SERVICE
# MAIL_HOST=smtp.example.com
# MAIL_PORT=587
# MAIL_SECURE=false

# Use a web route that the Flutter app can open directly.
# If you deploy with hash routing, keep this as /#/reset-password.
PASSWORD_RESET_URL=https://your-app/#/reset-password
```

The password reset endpoint hashes every token before persisting it. Emails are sent via Nodemailer using either a Gmail app-password setup or custom SMTP settings. The reset email opens the app directly on the reset screen and also includes the raw token so users can complete the reset inside the app if needed.

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

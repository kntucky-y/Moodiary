# Moodiary

Flutter + Node/Express stack for journaling, moods, and social chat. This fork now supports password recovery in addition to the existing email/password flow.

## Backend configuration

Create `backend/.env` with the existing values plus the following additions:

```
# Recommended for Mailgun using a verified Name.com domain
MAIL_HOST=smtp.mailgun.org
MAIL_PORT=587
MAIL_SECURE=false
MAIL_USER=postmaster@mg.yourdomain.com
MAIL_PASS=your-mailgun-smtp-password
MAIL_FROM="Moodiary <no-reply@yourdomain.com>"

# Optional fallback that avoids SMTP entirely (recommended on managed hosting if SMTP times out)
# RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxxx
```

The password reset endpoint hashes every code before persisting it. Emails are sent with one of these providers:
- `RESEND_API_KEY` set: sends through Resend HTTPS API (no SMTP ports).
- Otherwise: Nodemailer SMTP using Mailgun or another custom SMTP provider.

The reset email now contains only a 6-digit verification code. The user enters their email, the code, and a new password in the app.

## Mailgun and Name.com setup

1. Add your domain to Mailgun and choose the sending region.
2. Copy the DNS records Mailgun gives you into your Name.com DNS zone.
3. Wait until Mailgun marks the domain as verified.
4. Use the verified sender address from that domain for `MAIL_FROM`.
5. Configure the backend SMTP values above and restart the server.
6. Send a test reset request from the app and confirm the code arrives before testing the password change flow.

## Mobile configuration

### Backend URL

The mobile app reads the backend URL from `BACKEND_BASE_URL` at build time.
For production builds, pass the new DigitalOcean domain:

```
flutter build apk --dart-define=BACKEND_BASE_URL=https://api.your-domain.com
```

The Resources tab map uses OpenStreetMap and does not require Google Maps API keys or billing setup.

After updating dependencies run:

```
cd moodiary
flutter clean
flutter pub get
flutter run
```

## Auth flows

- **Forgot password** – tap “Forgot password?” on the login screen, enter your email, then use the 6-digit code from the email on the reset screen to choose a new password.
- **Email + password login** – the default login/registration fields remain the single source of truth for authentication now that social providers have been removed.

For questions or troubleshooting, see the inline comments in `backend/routes/auth.js` and `lib/screens/auth/login_screen.dart` for the specific data flows.

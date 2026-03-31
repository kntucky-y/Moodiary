# Moodiary

Flutter + Node/Express stack for journaling, moods, and social chat. This fork now supports password recovery plus Google/Facebook authentication.

## Backend configuration

Create `backend/.env` with the existing values plus the following additions:

```
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USER=your-user
MAIL_PASS=your-pass
MAIL_FROM="Moodiary <no-reply@moodiary.app>"
PASSWORD_RESET_URL=https://your-app/reset-password

GOOGLE_CLIENT_ID=your-google-oauth-client-id.apps.googleusercontent.com

FACEBOOK_APP_ID=1234567890
FACEBOOK_APP_SECRET=facebook-app-secret
```

The password reset endpoint hashes every token before persisting it. Emails are queued via Nodemailer; if mail creds are missing the server logs the reset link so you can test locally.

## Mobile configuration

1. Replace the placeholder IDs inside:
	- `android/app/src/main/res/values/strings.xml` (`facebook_app_id`, `facebook_client_token`, `fb_login_protocol_scheme`)
	- `ios/Runner/Info.plist` (`FacebookAppID`, `CFBundleURLTypes` entries for Google/Facebook)
2. Add the corresponding OAuth credentials in the Google Cloud console and Facebook Developers dashboard so the native SDKs can issue tokens tied to your bundle IDs.
3. Pass the Google/Facebook client IDs to Flutter via `--dart-define` so the mobile app can request tokens that match the backend audience:

```
flutter run \
	--dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client.apps.googleusercontent.com \
	--dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client.apps.googleusercontent.com \
	--dart-define=FACEBOOK_APP_ID=1234567890
```

4. Rebuild the Flutter app after updating the native values:

```
cd moodiary
flutter clean
flutter pub get
flutter run --dart-define=GOOGLE_CLIENT_ID=... (optional overrides)
```

## Auth flows

- **Forgot password** – tap “Forgot password?” on the login screen to send yourself a reset link. Use the new in-app reset screen to paste the token and choose a new password.
- **Google / Facebook login** – both buttons use the provider SDKs, exchange the secure tokens with the backend, and receive the same JWT used for the rest of the app. Existing email accounts are linked automatically when the provider reports the same email address.

> Tip: you can list multiple Google audiences for the backend verification by setting `GOOGLE_CLIENT_ID` to a comma-separated list (for example, mobile and web client IDs).

For questions or troubleshooting, see the inline comments in `backend/routes/auth.js` and `lib/screens/auth/login_screen.dart` for the specific data flows.

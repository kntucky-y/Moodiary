const String googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);

/// Optional web/iOS client id used by the GoogleSignIn plugin when running on
/// the web. Defaults to the server client id if not provided.
const String googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: googleServerClientId,
);

const String facebookAppId = String.fromEnvironment(
  'FACEBOOK_APP_ID',
  defaultValue: '',
);

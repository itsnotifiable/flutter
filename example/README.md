# Notifiable example

A small Flutter app for the `notifiable` package. Paste a public key, then enable notifications, identify a person, and open `/orders` or `/inbox` from a notification url.

From this folder:

```bash
flutter run
```

Turn on the iOS Push Notifications capability. On Android, add `google-services.json` and the Google Services plugin before expecting an FCM token. Connect still saves the subscriber when that token is missing.

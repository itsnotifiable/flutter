# Notifiable for Flutter

`notifiable` registers a Flutter app with [Notifiable](https://notifiable.sh), asks for notification permission, and identifies the person using the app. From the same client you can list their inbox, record that they opened or tapped a notification, and send events.

Import `package:notifiable/notifiable.dart`.

The package talks to `https://notifiable.sh/api` and sends `X-Notifiable-Key` on every request. The public key selects development or production. Apps do not pass a host or an environment name.

On iOS the package uses APNs. On Android it uses FCM. The app does not pass a push port.

## Install

Add the package from this repository:

```yaml
dependencies:
  notifiable:
    path: ../flutter
```

A git dependency can point at the `flutter` directory of the repository. Publishing to pub.dev is a later step.

iOS 13 or newer. Turn on the Push Notifications capability for the app target. The plugin receives the APNs device token through Flutter's application delegate. You do not add AppDelegate code, and the plugin does not swizzle `UIApplication`.

Android needs the usual Firebase setup so FCM can return a token:

1. Add `google-services.json` to `android/app/`.
2. Apply the Google Services plugin in the app Gradle files.

If Firebase is not initialized, the token is empty and connect still saves the subscriber. The plugin turns off Firebase's automatic startup provider so a missing `google-services.json` does not crash the process. An app that already initializes Firebase keeps doing that.

## Configure

Wrap the app in `Notifiable`. It builds the client and calls `start()` when the widget mounts. Permission is asked only when you call it from a button, or when the dashboard asks for the prompt.

```dart
import 'package:notifiable/notifiable.dart';

Notifiable(
  publicKey: 'ntf_pub_...',
  deepLinks: const [
    DeepLink(path: '/orders', label: 'Orders'),
    DeepLink(path: '/inbox', label: 'Inbox'),
  ],
  onDeepLink: (url) {
    // Open this route.
  },
  child: const Home(),
)
```

| Argument | What you pass |
| --- | --- |
| `publicKey` | The key from the Notifiable dashboard. A blank key stops setup before any request. |
| `deepLinks` | Screens Notifiable can link to. Each one is `DeepLink(path:, label:)`. Saved when connect succeeds. Omit it to skip that save. |
| `onDeepLink` | Called with a notification url when someone taps a development preview. |
| `logger` | Optional `debug`, `info`, `warn`, and `error` callbacks. |
| `storage` | Your own `getItem` / `setItem` / `removeItem` store. Omit it to use `shared_preferences`. |
| `client` | A client you already built with `NotifiableClient`. The widget starts that client and ignores `publicKey`. |
| `child` | The app tree. `Notifiable.of(context)` works anywhere under this widget. |

Read the client from any child:

```dart
final notifiable = Notifiable.of(context);

Text(notifiable.snapshot.ready ? 'Connected' : 'Connecting…');
```

You can also build the client yourself. Use this when the app is not rooted in the widget.

```dart
final notifiable = NotifiableClient(
  publicKey: 'ntf_pub_...',
  deepLinks: const [DeepLink(path: '/orders', label: 'Orders')],
  onDeepLink: (url) {
    // Open this route.
  },
);

await notifiable.start();
await notifiable.requestPermission();
await notifiable.identify(email: 'ada@example.com', externalId: 'user_123');
```

### Public key

Create the key in the Notifiable dashboard and pass it as `publicKey`. A blank key throws `invalid_config` before the app connects.

Use the **development** key while you build, including on the iOS simulator and the Android emulator. Use the **production** key in the build you ship. The key is what switches the app between those two modes.

The same install is remembered on the device under `notifiable.session.` plus the public key. Opening the app again updates that subscriber instead of creating a new one. Permission can stay denied or undecided. The subscriber still exists.

### Permission

Ask from a button, or let the dashboard request the prompt. Both go through the system prompt and then save the answer.

```dart
FilledButton(
  onPressed: () async {
    await Notifiable.of(context).requestPermission();
  },
  child: const Text('Enable notifications'),
)
```

On iOS, `provider` is `apns` and the token is the APNs device token as lowercase hex. On Android, `provider` is `fcm` and the token is the FCM registration token. A granted permission with an empty token is saved as `not_determined` on connect, without `provider` or `token`.

## Development and production

| | Development key | Production key |
| --- | --- | --- |
| First launch | A sheet asks you to show or hide the Notifiable mark | No sheet |
| On screen | A draggable mark. Tap it to compare this app's bundle id or package name with the dashboard | Nothing from Notifiable is drawn over the app |
| Notifications | A recent notification can appear as a toast at the top of the screen while the app is in the foreground and permission is `granted` | The system displays the notification |
| Diagnostics | Failed SDK calls can be shared with Notifiable. The switch starts on | Nothing is sent |

A development key polls the inbox every 5 seconds while a subscriber id exists, permission is `granted`, and the app is resumed. A recent unread alert appears at the top. The toast records the open. A tap records a click when the notification has a delivery id or an `opt` value on `url`, then calls `onDeepLink`. Hiding the mark does not stop the poll. On the iOS simulator, Command N shows the mark again.

The mark compares the dashboard iOS bundle id, or the Android package name, with this app. A match shows a check. A mismatch names the identifier to paste into the dashboard, with a copy button. [Learn what is collected](https://notifiable.sh/sdk-diagnostics).

## NotifiableClient

`snapshot` is the live state. Widgets that call `Notifiable.of` rebuild when it changes.

Wait until `snapshot.ready` is true before `identify`, `inbox`, `notification`, `openNotification`, `clickDelivery`, or `track`. Those calls need the subscriber created at connect.

`snapshot.permission` is `granted`, `denied`, or `notDetermined`. The wire values are `granted`, `denied`, and `not_determined`.

`identify` attaches a real person to this device. `email`, `externalId`, `firstName`, and `lastName` are optional, and at least one is required. A blank email or a blank external id is rejected. After an email or an external id is saved, the subscriber is no longer anonymous.

```dart
final subscriber = await notifiable.identify(
  email: 'ada@example.com',
  externalId: 'user_123',
  firstName: 'Ada',
  lastName: 'Lovelace',
);
```

`inbox` returns one page of this subscriber's notifications. `openNotification` records an open. `clickDelivery` records a tap. `track` records an event for the connected subscriber.

```dart
final page = await notifiable.inbox(query: const InboxQuery(page: 1, opened: false));
await notifiable.openNotification(page.notifications.first.id);
await notifiable.track(
  'order.shipped',
  properties: const {
    'order': EventProperty.string('1001'),
    'express': EventProperty.bool(true),
  },
);
```

`setDevIndicator` and `setDiagnostics` remember the development mark and the diagnostics switch. A production key does not draw the mark and does not send reports.

## Errors

Failed calls throw `NotifiableError`. `snapshot.error` is the last failure from `start`, `requestPermission`, and `identify`.

| Code | What happened |
| --- | --- |
| `invalid_config` | The public key is blank, or identify was called without a field. |
| `invalid_public_key` | Notifiable rejected the key. |
| `network` | The request did not succeed, or the response was not the expected JSON. |
| `validation_failed` | A value was rejected. |
| `subscriber_not_found` | Connect has not finished, or the subscriber no longer exists. |
| `subscriber_limit` | The project cannot add another subscriber. |
| `rate_limited` | Too many requests. Wait and try again. |
| `missing_token` | Permission is granted and no device token was returned. Connect saves `not_determined` instead. |
| `missing_storage` | Session storage could not be opened. |
| `missing_provider` | `Notifiable.of` was called outside the widget. |
| `not_implemented` | Reserved. |

## Tests

From the `flutter` folder:

```bash
flutter test
```

The tests cover connect, the subscriber body, the permission prompt, a granted permission with no token, identify clearing the anonymous id, inbox parsing, fresh development notifications, the package check, and diagnostics.

## Example

`example/` is a small app. It stores a public key, connects, and opens `/orders` or `/inbox` when a notification url matches. Run it with `flutter run` from `example/` after the iOS capability and, on Android, `google-services.json` are in place.
# flutter

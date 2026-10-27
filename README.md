# Notifiable for Flutter

Register a Flutter app with [Notifiable](https://notifiable.sh): connect with a public key, ask for notification permission, identify the user, list their inbox, record opens and taps, and track events.

Import `package:notifiable_flutter/notifiable.dart` only. On iOS the package uses APNs; on Android it uses FCM. The app does not pass a push port.

## Install

Package on [pub.dev](https://pub.dev/packages/notifiable_flutter):

```bash
flutter pub add notifiable_flutter
```

Or add it to your app’s `pubspec.yaml` and run `flutter pub get`:

```yaml
dependencies:
  notifiable_flutter: ^0.1.0
```

Then import only this library:

```dart
import 'package:notifiable_flutter/notifiable.dart';
```

### Platform setup

**iOS:** iOS 13+. Enable the Push Notifications capability. The plugin receives the APNs token through Flutter’s application delegate — no AppDelegate swizzling.

**Android:** Add `google-services.json` and apply the Google Services plugin when you want an FCM token. If Firebase is not initialized, the token is empty and connect still saves the subscriber. A missing `google-services.json` does not crash startup.

## Integrate

Wrap the app in `Notifiable`. It builds the client and calls `start()` on mount.

```dart
import 'package:notifiable_flutter/notifiable.dart';

Notifiable(
  publicKey: 'ntf_pub_...',
  deepLinks: const [
    DeepLink(path: '/orders', label: 'Orders'),
    DeepLink(path: '/inbox', label: 'Inbox'),
  ],
  onDeepLink: (url) {
    // Open this route with your navigator.
  },
  child: const Home(),
)
```

| Argument | Required | Description |
| --- | --- | --- |
| `publicKey` | yes* | Key from the Notifiable dashboard. Development key while building; production key for the store build. |
| `deepLinks` | no | Routes Notifiable can link to: `DeepLink(path:, label:)`. |
| `onDeepLink` | no | Called with a notification url (e.g. development toast tap). |
| `logger` | no | `debug` / `info` / `warn` / `error` callbacks. |
| `storage` | no | Custom store. Defaults to `shared_preferences`. |
| `client` | no | Existing `NotifiableClient`. Ignores `publicKey`. |
| `child` | yes | App tree. |

\*Required unless you pass `client`.

Read the client from any child:

```dart
final notifiable = Notifiable.of(context);

Text(notifiable.snapshot.ready ? 'Connected' : 'Connecting…');
```

Or build the client yourself (no widget):

```dart
final notifiable = NotifiableClient(
  publicKey: 'ntf_pub_...',
  deepLinks: const [DeepLink(path: '/orders', label: 'Orders')],
  onDeepLink: (url) { /* navigate */ },
);

await notifiable.start();
await notifiable.requestPermission();
await notifiable.identify(email: 'ada@example.com', externalId: 'user_123');
```

### Permission

```dart
FilledButton(
  onPressed: () async {
    await Notifiable.of(context).requestPermission();
  },
  child: const Text('Enable notifications'),
)
```

Or ask from the Notifiable dashboard — the next connect opens the system prompt. On iOS, `provider` is `apns` (lowercase hex token). On Android, `provider` is `fcm`. A granted permission with an empty token is saved as `not_determined` on connect.

## NotifiableClient API

Wait until `snapshot.ready` is true before `identify`, `inbox`, `notification`, `openNotification`, `clickDelivery`, or `track`.

### State (`snapshot`)

| Field | Meaning |
| --- | --- |
| `ready` | Connect finished and the subscriber was saved. |
| `permission` | `granted` / `denied` / `notDetermined` (wire: `not_determined`). |
| `subscriber` | Device/person record, or null until connect. |
| `clientConfig` | Dashboard app record, or null. |
| `deepLinks` | Saved routes, or null. |
| `devIndicator` / `diagnostics` | Development mark and crash-sharing choices. |
| `error` | Last `NotifiableError`, or null. |

Widgets that call `Notifiable.of` rebuild when the snapshot changes.

### Methods

**`start()`** — Connects. The widget calls this on mount.

**`requestPermission()`** — System prompt, then save. Returns the new permission.

**`identify(...)`** — Attach a signed-in user. Pass at least one of `email`, `externalId`, `firstName`, `lastName` (email/externalId preferred). Blank email or external id is rejected.

```dart
await notifiable.identify(
  email: 'ada@example.com',
  externalId: 'user_123',
  firstName: 'Ada',
  lastName: 'Lovelace',
);
```

**`inbox({InboxQuery? query})`** — One page of notifications (normally 20).

```dart
final page = await notifiable.inbox(
  query: const InboxQuery(page: 1, opened: false),
);
```

**`notification(id)`** / **`openNotification(id)`** / **`clickDelivery(deliveryId)`** — Load, mark opened, record tap.

**`track(name, {properties})`** — Event for the connected subscriber.

```dart
await notifiable.track(
  'order.shipped',
  properties: const {
    'order': EventProperty.string('1001'),
    'express': EventProperty.bool(true),
  },
);
```

**`setDevIndicator`** / **`setDiagnostics`** — Development mark and diagnostics. No-ops for a production key.

## Development vs production

| | Development key | Production key |
| --- | --- | --- |
| First launch | Sheet to show/hide the Notifiable mark | No sheet |
| On screen | Draggable mark (bundle id / package check) | Nothing overlaid |
| Notifications | Recent unread can appear as top toasts while foreground + granted | System displays them |
| Diagnostics | Failed SDK calls can be shared | Nothing sent |

On the iOS simulator, **⌘N** shows the mark again.

## Errors

Failed calls throw `NotifiableError`. `snapshot.error` is the last failure from `start`, `requestPermission`, and `identify`.

| Code | Meaning |
| --- | --- |
| `invalid_config` | Blank public key, or identify without a field. |
| `invalid_public_key` | Key rejected. |
| `network` | Request failed or unexpected JSON. |
| `validation_failed` | Rejected value. |
| `subscriber_not_found` | Connect not finished, or subscriber gone. |
| `subscriber_limit` | Project cannot add another subscriber. |
| `rate_limited` | Too many requests. |
| `missing_token` | Granted permission but no device token (connect saves `not_determined`). |
| `missing_storage` | Session storage could not be opened. |
| `missing_provider` | `Notifiable.of` outside the widget. |
| `not_implemented` | Reserved. |

## Example

`example/` stores a public key, connects, and opens `/orders` or `/inbox` from notification urls. From `example/`: `flutter run` (after iOS Push capability and, on Android, `google-services.json`).

## Tests

```bash
cd flutter && flutter test
```

## For AI agents

### Rules

1. Import only `package:notifiable_flutter/notifiable.dart`. Do not deep-import `lib/src`.
2. Mount one `Notifiable(...)` around the app (or build `NotifiableClient` and call `start()`).
3. Pass `publicKey`, optional `deepLinks`, and `onDeepLink` that navigates with the app’s router.
4. Wait for `snapshot.ready` before identify / inbox / track APIs. Call `requestPermission()` from a button.
5. After sign-in, call `identify` with `email` and/or `externalId`.
6. On Android, ensure Firebase / `google-services.json` only when an FCM token is required; connect still works without it.
7. Do not invent hosts, env names, or CORS settings. Development key for local builds; production key for release.

### Integration prompt

Copy this into a coding agent when wiring the SDK into an existing Flutter app:

```text
Integrate the Notifiable Flutter package (package:notifiable_flutter/notifiable.dart) into this Flutter project.

1. Add `notifiable_flutter: ^0.1.0` to pubspec.yaml and run `flutter pub get`.
2. On iOS, enable the Push Notifications capability. On Android, add google-services.json and the Google Services plugin if the app should receive FCM tokens; do not crash if Firebase is missing.
3. Wrap the root MaterialApp / navigator in Notifiable(publicKey: ..., deepLinks: ..., onDeepLink: ..., child: ...).
4. Pass publicKey from the project’s config (development key for debug, production key for release).
5. Implement onDeepLink to push the notification path with this app’s Navigator / go_router / auto_route.
6. After sign-in, when snapshot.ready is true, call identify(email: ..., externalId: ...).
7. Add an “Enable notifications” button that calls requestPermission().
8. If there is an inbox screen, use inbox(), openNotification(id), and clickDelivery(deliveryId).
9. Do not explain CORS, API hosts, or environments — only the public key. Keep changes minimal and match existing project patterns.
```

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notifiable/notifiable.dart';
import 'package:notifiable/src/domain/environment.dart';
import 'package:notifiable/src/domain/inbox.dart';
import 'package:notifiable/src/domain/locale.dart';
import 'package:notifiable/src/domain/models.dart';
import 'package:notifiable/src/domain/subscriber.dart';
import 'package:notifiable/src/internal/storage.dart';
import 'package:notifiable/src/platform/flutter_platform.dart';
import 'package:notifiable/src/transport/http_client.dart';

void main() {
  test('blank key throws before a request', () {
    final transport = StubTransport((_) => success({}));

    expect(
      () => NotifiableClient(
        publicKey: '  ',
        device: FakeDevice(),
        transport: transport,
      ),
      throwsA(
        isA<NotifiableError>().having(
          (error) => error.code,
          'code',
          NotifiableErrorCode.invalidConfig,
        ),
      ),
    );
    expect(transport.recorded, isEmpty);
  });

  test('envelope maps api errors', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('development'));
      }

      if (call.url.contains('subscribers') && !call.url.contains('notifications')) {
        return success(subscriber(prompt: false));
      }

      return {
        'status': 'error',
        'code': 'VALIDATION_FAILED',
        'message': 'Invalid',
        'error': {
          'details': [
            {'message': 'Email is invalid.'},
            {'message': 'Try another.'},
          ],
        },
      };
    });
    final client = makeClient(transport);
    await client.start();
    final error = await expectError(() => client.track('opened'));

    expect(error.code, NotifiableErrorCode.validationFailed);
    expect(error.message, 'Email is invalid. Try another.');
  });

  test('subscriber body prompts and then saves the token', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('development'));
      }

      if (call.url.contains('deep-links')) {
        return success({
          'links': [
            {'path': '/orders', 'label': 'Orders'},
          ],
        });
      }

      final prompted = call.body['prompted'] == true;
      return success(
        subscriber(prompt: !prompted, permission: prompted ? 'granted' : 'not_determined'),
      );
    });
    final push = FakePush()..deviceToken = 'abc123';
    final storage = MemoryStorage();
    final client = makeClient(
      transport,
      push: push,
      storage: storage,
      deepLinks: const [DeepLink(path: '/orders', label: 'Orders')],
    );

    await client.start();

    final posts = transport.recorded
        .where((call) => call.method == 'POST' && call.url.contains('/subscribers'))
        .toList();
    expect(posts, hasLength(2));
    final first = posts[0].body;
    expect(first['sdk'], 'flutter');
    expect(first['platform'], 'ios');
    expect(first['permission'], 'not_determined');
    expect(first.containsKey('provider'), isFalse);
    expect(first.containsKey('token'), isFalse);
    expect(first.containsKey('prompted'), isFalse);
    expect(first['language'], 'en');
    expect(first['country_code'], 'MA');
    expect(first['sdk_version'], notifiableSdkVersion);
    expect(first['anonymous_id'], isA<String>());
    expect(posts[0].key, 'ntf_pub_test');

    final second = posts[1].body;
    expect(second['prompted'], isTrue);
    expect(second['permission'], 'granted');
    expect(second['provider'], 'apns');
    expect(second['token'], 'abc123');
    expect(second.containsKey('anonymous_id'), isFalse);
    expect(push.requests, 1);
    expect(client.snapshot.permission, PermissionStatus.granted);
    expect(client.snapshot.deepLinks, const [DeepLink(path: '/orders', label: 'Orders')]);

    final saved = await storage.getItem(sessionKey('ntf_pub_test'));
    expect(saved, contains(first['device_id']));

    final again = makeClient(transport, push: push, storage: storage);
    await again.start();
    final later = transport.recorded
        .where((call) => call.method == 'POST' && call.url.contains('/subscribers'))
        .toList();
    expect(later.last.body['device_id'], first['device_id']);
  });

  test('granted permission without a token saves not_determined', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('production'));
      }

      return success(subscriber(prompt: false));
    });
    final push = FakePush()
      ..status = PermissionStatus.granted
      ..deviceToken = '   ';
    final client = makeClient(transport, push: push);

    await client.start();

    final body = transport.recorded.firstWhere((call) => call.method == 'POST').body;
    expect(body['permission'], 'not_determined');
    expect(body.containsKey('provider'), isFalse);
    expect(body.containsKey('token'), isFalse);
    expect(client.snapshot.permission, PermissionStatus.notDetermined);
  });

  test('dashboard prompt clears without a token', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('development'));
      }

      final prompted = call.body['prompted'] == true;
      return success(subscriber(prompt: !prompted, permission: 'not_determined'));
    });
    final push = FakePush()..deviceToken = null;
    final client = makeClient(transport, push: push);

    await client.start();

    final posts = transport.recorded
        .where((call) => call.method == 'POST' && call.url.contains('/subscribers'))
        .toList();
    expect(posts, hasLength(2));
    expect(posts[1].body['prompted'], isTrue);
    expect(posts[1].body['permission'], 'not_determined');
    expect(posts[1].body.containsKey('token'), isFalse);
    expect(push.requests, 1);
    expect(client.snapshot.error, isNull);
  });

  test('explicit requestPermission requires a token', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('production'));
      }

      return success(subscriber(prompt: false));
    });
    final push = FakePush()..deviceToken = null;
    final client = makeClient(transport, push: push);
    await client.start();

    await expectLater(
      client.requestPermission(),
      throwsA(
        isA<NotifiableError>().having(
          (error) => error.code,
          'code',
          NotifiableErrorCode.missingToken,
        ),
      ),
    );
  });

  test('identify clears the anonymous id', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('production'));
      }

      if (call.method == 'PATCH') {
        return success(subscriber(prompt: false, permission: 'not_determined', externalId: 'user_123'));
      }

      return success(subscriber(prompt: false));
    });
    final client = makeClient(transport);
    await client.start();
    final identified = await client.identify(email: 'ada@example.com', externalId: 'user_123');
    final patch = transport.recorded.firstWhere((call) => call.method == 'PATCH');

    expect(patch.body['email'], 'ada@example.com');
    expect(patch.body['external_id'], 'user_123');
    expect(patch.body.containsKey('anonymous_id'), isTrue);
    expect(patch.body['anonymous_id'], isNull);
    expect(identified.externalId, 'user_123');
    expect(transport.recorded.where((call) => call.url.contains('diagnostics')), isEmpty);
  });

  test('inbox parsing keeps the delivery id from opt', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('production'));
      }

      if (call.method == 'POST') {
        return success(subscriber(prompt: false));
      }

      expect(call.url, contains('page=1'));
      expect(call.url, contains('opened=false'));
      return success({
        'notifications': [
          {
            'id': 'note_1',
            'title': 'Hello',
            'body': 'World',
            'url': '/orders?opt=delivery_1',
            'opened': false,
            'created_at': '2026-10-17T22:00:00Z',
            'alert': true,
            'delivery_id': '',
          },
          {'id': ''},
        ],
        'page': 1,
        'per_page': 20,
        'total': 1,
      });
    });
    final client = makeClient(transport);
    await client.start();
    final page = await client.inbox(query: const InboxQuery(page: 1, opened: false));

    expect(page.perPage, 20);
    expect(page.total, 1);
    expect(page.notifications, hasLength(1));
    expect(page.notifications.single.title, 'Hello');
    expect(notificationDeliveryId(page.notifications.single), 'delivery_1');
  });

  test('diagnostics are sent once in development and never in production', () async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('development'));
      }

      if (call.url.contains('diagnostics')) {
        return success({'accepted': 1});
      }

      if (call.url.contains('notifications')) {
        return {
          'status': 'error',
          'code': 'RATE_LIMIT_EXCEEDED',
          'message': 'Slow down',
        };
      }

      return success(subscriber(prompt: false));
    });
    final client = makeClient(transport);
    await client.start();

    await expectError(() => client.inbox());
    await expectError(() => client.inbox());
    await waitUntil(
      () => transport.recorded.where((call) => call.url.contains('diagnostics')).length == 1,
    );

    final report = transport.recorded.firstWhere((call) => call.url.contains('diagnostics'));
    final items = report.body['items'] as List;
    expect(items, hasLength(1));
    final item = items.single as Map;
    expect(item['sdk'], 'flutter');
    expect(item['platform'], 'ios');

    await client.setDiagnostics(enabled: false);
    final before = transport.recorded.where((call) => call.url.contains('diagnostics')).length;
    await expectError(() => client.track('later'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.recorded.where((call) => call.url.contains('diagnostics')).length, before);

    final production = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('production'));
      }

      if (call.url.contains('diagnostics')) {
        return success({'accepted': 1});
      }

      if (call.url.contains('notifications')) {
        return {
          'status': 'error',
          'code': 'RATE_LIMIT_EXCEEDED',
          'message': 'Slow down',
        };
      }

      return success(subscriber(prompt: false));
    });
    final productionClient = makeClient(production);
    await productionClient.start();
    await expectError(() => productionClient.inbox());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(production.recorded.where((call) => call.url.contains('diagnostics')), isEmpty);
  });

  test('fresh notifications, package check, and locale', () {
    const now = 1700000000000;
    final recent = notification('recent', now - 1000, opened: false, alert: true);
    final stale = notification('stale', now - 9000, opened: false, alert: true);
    final opened = notification('opened', now - 1000, opened: true, alert: true);
    final silent = notification('silent', now - 1000, opened: false, alert: false);
    final soon = notification('soon', now + 1000, opened: false, alert: true);
    final fresh = selectFreshNotifications(
      [recent, stale, opened, silent, soon],
      nowMs: now,
      seen: {'recent'},
    );

    expect(fresh.map((item) => item.id), ['soon']);
    expect(packageCheck(configured: 'app', applicationId: 'app'), PackageCheck.match);
    expect(packageCheck(configured: 'other', applicationId: 'app'), PackageCheck.mismatch);
    expect(packageCheck(configured: null, applicationId: 'app'), PackageCheck.mismatch);
    expect(packageCheck(configured: 'app', applicationId: null), isNull);
    expect(packageCheck(configured: 'app', applicationId: ''), isNull);
    expect(localeParts('en-MA').language, 'en');
    expect(localeParts('en-MA').countryCode, 'MA');
    expect(localeParts('en_MA').countryCode, 'MA');
    expect(deviceAddress('127.0.0.1'), isNull);
    expect(deviceAddress('0.0.0.0'), isNull);
    expect(deviceAddress('10.0.0.8'), '10.0.0.8');
    expect(crashFingerprint(type: 'Error', message: 'Nope', frames: const []), 'Error|Nope|');
    expect(pushProviderFor(ios: true), PushProvider.apns);
    expect(pushProviderFor(ios: false), PushProvider.fcm);
    expect(mobilePlatformFor(ios: true), MobilePlatform.ios);
    expect(mobilePlatformFor(ios: false), MobilePlatform.android);
  });

  testWidgets('missing provider throws', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              () => Notifiable.of(context),
              throwsA(
                isA<NotifiableError>().having(
                  (error) => error.code,
                  'code',
                  NotifiableErrorCode.missingProvider,
                ),
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('the widget shows its child', (tester) async {
    final transport = StubTransport((call) {
      if (call.url.contains('client-config')) {
        return success(clientConfig('production'));
      }

      return success(subscriber(prompt: false));
    });
    final client = makeClient(transport);

    await tester.pumpWidget(
      MaterialApp(
        home: Notifiable(client: client, child: const Text('Home')),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    await tester.pump();
    expect(client.snapshot.ready, isTrue);
  });
}

NotifiableClient makeClient(
  StubTransport transport, {
  FakePush? push,
  MemoryStorage? storage,
  List<DeepLink>? deepLinks,
}) {
  return NotifiableClient(
    publicKey: 'ntf_pub_test',
    push: push ?? FakePush(),
    storage: storage ?? MemoryStorage(),
    device: FakeDevice(),
    deepLinks: deepLinks,
    transport: transport,
  );
}

Map<String, Object?> success(Object? data) => {'status': 'success', 'data': data};

Map<String, Object?> clientConfig(String environment) => {
  'environment': environment,
  'app': {
    'name': 'Example',
    'description': 'Demo',
    'icon': 'https://notifiable.sh/favicon.png',
  },
  'ios': {'bundle_id': 'sh.notifiable.demo'},
};

Map<String, Object?> subscriber({
  required bool prompt,
  String permission = 'not_determined',
  String? externalId,
}) {
  return {
    'id': '11111111-1111-4111-8111-111111111111',
    'environment': 'development',
    'platform': 'ios',
    'permission': permission,
    'prompt_permission': prompt,
    'sdk': 'flutter',
    'device_id': 'device',
    if (externalId != null) 'external_id': externalId,
  };
}

SubscriberNotification notification(
  String id,
  int createdMs, {
  required bool opened,
  required bool alert,
}) {
  return SubscriberNotification(
    id: id,
    title: id,
    body: '',
    alert: alert,
    opened: opened,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true).toIso8601String(),
  );
}

Future<NotifiableError> expectError(Future<Object?> Function() body) async {
  try {
    await body();
    fail('Expected an error');
  } on NotifiableError catch (error) {
    return error;
  }
}

Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for a condition');
}

class StubTransport implements HttpTransport {
  StubTransport(this.handler);

  final Map<String, Object?> Function(Call call) handler;
  final List<Call> recorded = [];

  @override
  Future<HttpResult> send({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    String? body,
  }) async {
    final decoded = body == null
        ? <String, Object?>{}
        : (jsonDecode(body) as Map).map((key, value) => MapEntry(key.toString(), value));
    final call = Call(
      method: method,
      url: url.toString(),
      key: headers['X-Notifiable-Key'],
      body: decoded,
    );
    recorded.add(call);
    return HttpResult(statusCode: 200, body: jsonEncode(handler(call)));
  }
}

class Call {
  Call({required this.method, required this.url, required this.key, required this.body});

  final String method;
  final String url;
  final String? key;
  final Map<String, Object?> body;
}

class FakePush implements PushPort {
  @override
  final provider = PushProvider.apns;

  @override
  final allowMissingToken = true;

  PermissionStatus status = PermissionStatus.notDetermined;
  String? deviceToken;
  var requests = 0;

  @override
  Future<PermissionStatus> permissionStatus() async => status;

  @override
  Future<PermissionStatus> requestPermission() async {
    requests += 1;
    status = PermissionStatus.granted;
    return status;
  }

  @override
  Future<String?> token() async => deviceToken;

  @override
  Future<String?> registrationError() async => null;
}

class FakeDevice implements DevicePort {
  @override
  Future<DeviceProfile> profile() async {
    return const DeviceProfile(
      platform: MobilePlatform.ios,
      locale: 'en-MA',
      timezone: 'Africa/Casablanca',
      model: 'iPhone',
      manufacturer: 'Apple',
      appVersion: '1.0',
      ip: '10.0.0.8',
    );
  }

  @override
  Future<String?> applicationId() async => 'sh.notifiable.example';

  @override
  void copy(String value) {}

  @override
  Future<bool> get isSimulator async => false;
}

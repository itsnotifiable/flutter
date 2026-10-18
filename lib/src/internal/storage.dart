import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/errors.dart';
import '../domain/ports.dart';
import '../domain/subscriber.dart';

String sessionKey(String publicKey) => 'notifiable.session.$publicKey';

String diagnosticsKey(String publicKey) => 'notifiable.diagnostics.$publicKey';

String devIndicatorKey(String publicKey) => 'notifiable.dev-indicator.$publicKey';

class MemoryStorage implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem(String key) async => _values[key];

  @override
  Future<void> setItem(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    _values.remove(key);
  }
}

class SharedPreferencesStorage implements KeyValueStore {
  SharedPreferences? _preferences;

  Future<SharedPreferences> _load() async {
    final existing = _preferences;

    if (existing != null) {
      return existing;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      return preferences;
    } catch (error) {
      throw NotifiableError(NotifiableErrorCode.missingStorage, error.toString());
    }
  }

  @override
  Future<String?> getItem(String key) async {
    final preferences = await _load();
    return preferences.getString(key);
  }

  @override
  Future<void> setItem(String key, String value) async {
    final preferences = await _load();
    await preferences.setString(key, value);
  }

  @override
  Future<void> removeItem(String key) async {
    final preferences = await _load();
    await preferences.remove(key);
  }
}

Future<StoredSession?> loadSession({
  required KeyValueStore storage,
  required String publicKey,
}) async {
  final raw = await storage.getItem(sessionKey(publicKey));

  if (raw == null) {
    return null;
  }

  try {
    final json = jsonDecode(raw);

    if (json is! Map) {
      return null;
    }

    final deviceId = json['deviceId'];

    if (deviceId is! String || deviceId.isEmpty) {
      return null;
    }

    return StoredSession(
      deviceId: deviceId,
      subscriberId: _text(json['subscriberId']),
      pushToken: _text(json['pushToken']),
      anonymousId: _text(json['anonymousId']),
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveSession({
  required KeyValueStore storage,
  required String publicKey,
  required StoredSession session,
}) async {
  final raw = jsonEncode({
    'deviceId': session.deviceId,
    'subscriberId': session.subscriberId,
    'pushToken': session.pushToken,
    'anonymousId': session.anonymousId,
  });
  await storage.setItem(sessionKey(publicKey), raw);
}

Future<T?> loadChoice<T>(
  KeyValueStore storage,
  String key,
  T? Function(String? raw) parse,
) async {
  return parse(await storage.getItem(key));
}

Future<void> saveChoice({
  required KeyValueStore storage,
  required String key,
  required String value,
}) async {
  await storage.setItem(key, value);
}

String? _text(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }

  return value;
}

String createId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

const _ulidAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String createUlid([int? time]) {
  final millis = time ?? DateTime.now().millisecondsSinceEpoch;
  return _encodeTime(millis) + _encodeRandom();
}

String _encodeTime(int time) {
  var value = time;
  final chars = <String>[];

  for (var index = 0; index < 10; index++) {
    chars.add(_ulidAlphabet[value % 32]);
    value ~/= 32;
  }

  return chars.reversed.join();
}

String _encodeRandom() {
  final bytes = List<int>.generate(10, (_) => Random.secure().nextInt(256));
  var buffer = 0;
  var bits = 0;
  final encoded = StringBuffer();

  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;

    while (bits >= 5) {
      bits -= 5;
      encoded.write(_ulidAlphabet[(buffer >> bits) & 31]);
    }
  }

  return encoded.toString();
}

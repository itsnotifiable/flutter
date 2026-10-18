import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/locale.dart';
import '../domain/ports.dart';
import '../domain/subscriber.dart';

const notifiableChannelName = 'sh.notifiable/notifiable';

PushProvider pushProviderFor({required bool ios}) {
  return ios ? PushProvider.apns : PushProvider.fcm;
}

MobilePlatform mobilePlatformFor({required bool ios}) {
  return ios ? MobilePlatform.ios : MobilePlatform.android;
}

class FlutterPushPort implements PushPort {
  FlutterPushPort({MethodChannel? channel, bool? ios})
    : _channel = channel ?? const MethodChannel(notifiableChannelName),
      _ios = ios ?? Platform.isIOS;

  final MethodChannel _channel;
  final bool _ios;

  @override
  PushProvider get provider => pushProviderFor(ios: _ios);

  @override
  bool get allowMissingToken => true;

  @override
  Future<PermissionStatus> permissionStatus() async {
    try {
      final raw = await _channel.invokeMethod<String>('permissionStatus');
      return PermissionStatus.parse(raw) ?? PermissionStatus.notDetermined;
    } catch (_) {
      return PermissionStatus.notDetermined;
    }
  }

  @override
  Future<PermissionStatus> requestPermission() async {
    try {
      final raw = await _channel.invokeMethod<String>('requestPermission');
      return PermissionStatus.parse(raw) ?? PermissionStatus.notDetermined;
    } catch (_) {
      return PermissionStatus.notDetermined;
    }
  }

  @override
  Future<String?> token() async {
    try {
      final value = await _channel.invokeMethod<String>('getToken');
      final token = value?.trim();

      if (token == null || token.isEmpty) {
        return null;
      }

      return token;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> registrationError() async {
    try {
      return await _channel.invokeMethod<String>('registrationError');
    } catch (_) {
      return null;
    }
  }
}

class FlutterDevicePort implements DevicePort {
  FlutterDevicePort({MethodChannel? channel, bool? ios})
    : _channel = channel ?? const MethodChannel(notifiableChannelName),
      _ios = ios ?? Platform.isIOS;

  final MethodChannel _channel;
  final bool _ios;
  Map<String, Object?>? _profile;

  @override
  Future<DeviceProfile> profile() async {
    final raw = await _read();
    return DeviceProfile(
      platform: mobilePlatformFor(ios: _ios),
      osVersion: _text(raw['osVersion']),
      locale: _text(raw['locale']) ?? Platform.localeName,
      timezone: _text(raw['timezone']),
      model: _text(raw['model']),
      manufacturer: _text(raw['manufacturer']) ?? (_ios ? 'Apple' : null),
      appVersion: _text(raw['appVersion']),
      ip: await _localIpv4(),
    );
  }

  @override
  Future<String?> applicationId() async {
    final raw = await _read();
    return _text(raw['applicationId']);
  }

  @override
  Future<bool> get isSimulator async {
    final raw = await _read();
    return raw['isSimulator'] == true;
  }

  @override
  void copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
  }

  Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('openUrl', url);
    } catch (_) {}
  }

  Future<Map<String, Object?>> _read() async {
    final cached = _profile;

    if (cached != null) {
      return cached;
    }

    try {
      final result = await _channel.invokeMethod<Object?>('deviceProfile');

      if (result is Map) {
        _profile = result.map((key, value) => MapEntry(key.toString(), value));
        return _profile!;
      }
    } catch (_) {}

    _profile = {};
    return _profile!;
  }

  Future<String?> _localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final filtered = deviceAddress(address.address);

          if (filtered != null) {
            return filtered;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

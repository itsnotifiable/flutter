enum PermissionStatus {
  granted('granted'),
  denied('denied'),
  notDetermined('not_determined');

  const PermissionStatus(this.value);

  final String value;

  static PermissionStatus? parse(String? raw) => _match(values, raw);
}

enum DevicePlatform {
  ios('ios'),
  android('android'),
  web('web');

  const DevicePlatform(this.value);

  final String value;

  static DevicePlatform? parse(String? raw) => _match(values, raw);
}

enum MobilePlatform {
  ios('ios'),
  android('android');

  const MobilePlatform(this.value);

  final String value;

  static MobilePlatform? parse(String? raw) => _match(values, raw);
}

enum PushProvider {
  apns('apns'),
  fcm('fcm'),
  webPush('web_push');

  const PushProvider(this.value);

  final String value;

  static PushProvider? parse(String? raw) => _match(values, raw);
}

T? _match<T>(List<T> values, String? raw) {
  if (raw == null) {
    return null;
  }

  for (final value in values) {
    final wire = switch (value) {
      PermissionStatus status => status.value,
      DevicePlatform platform => platform.value,
      MobilePlatform platform => platform.value,
      PushProvider provider => provider.value,
      _ => null,
    };

    if (wire == raw) {
      return value;
    }
  }

  return null;
}

enum ClientEnvironment {
  development('development'),
  production('production');

  const ClientEnvironment(this.value);

  final String value;

  static ClientEnvironment? parse(String? raw) {
    for (final value in values) {
      if (value.value == raw) {
        return value;
      }
    }

    return null;
  }
}

class Subscriber {
  const Subscriber({
    required this.id,
    required this.environment,
    required this.platform,
    required this.permission,
    required this.promptPermission,
    this.sdk,
    this.provider,
    this.deviceId,
    this.externalId,
    this.anonymousId,
  });

  final String id;
  final String environment;
  final DevicePlatform platform;
  final PermissionStatus permission;
  final String? sdk;
  final PushProvider? provider;
  final String? deviceId;
  final String? externalId;
  final String? anonymousId;
  final bool promptPermission;
}

class StoredSession {
  const StoredSession({
    required this.deviceId,
    this.subscriberId,
    this.pushToken,
    this.anonymousId,
  });

  final String deviceId;
  final String? subscriberId;
  final String? pushToken;
  final String? anonymousId;

  StoredSession copyWith({
    String? deviceId,
    String? subscriberId,
    String? pushToken,
    String? anonymousId,
    bool clearSubscriberId = false,
    bool clearPushToken = false,
    bool clearAnonymousId = false,
  }) {
    return StoredSession(
      deviceId: deviceId ?? this.deviceId,
      subscriberId: clearSubscriberId ? null : subscriberId ?? this.subscriberId,
      pushToken: clearPushToken ? null : pushToken ?? this.pushToken,
      anonymousId: clearAnonymousId ? null : anonymousId ?? this.anonymousId,
    );
  }
}

class DeviceProfile {
  const DeviceProfile({
    required this.platform,
    this.osVersion,
    this.locale,
    this.timezone,
    this.model,
    this.manufacturer,
    this.appVersion,
    this.ip,
  });

  final MobilePlatform platform;
  final String? osVersion;
  final String? locale;
  final String? timezone;
  final String? model;
  final String? manufacturer;
  final String? appVersion;
  final String? ip;
}

class SubscriberWrite {
  const SubscriberWrite({
    required this.deviceId,
    required this.platform,
    required this.permission,
    this.provider,
    this.token,
    this.anonymousId,
    this.prompted,
    this.osVersion,
    this.locale,
    this.timezone,
    this.model,
    this.manufacturer,
    this.appVersion,
    this.ip,
    this.language,
    this.countryCode,
    this.sdkVersion,
  });

  final String deviceId;
  final MobilePlatform platform;
  final PermissionStatus permission;
  final PushProvider? provider;
  final String? token;
  final String? anonymousId;
  final bool? prompted;
  final String? osVersion;
  final String? locale;
  final String? timezone;
  final String? model;
  final String? manufacturer;
  final String? appVersion;
  final String? ip;
  final String? language;
  final String? countryCode;
  final String? sdkVersion;
}

class SubscriberIdentity {
  const SubscriberIdentity({
    this.email,
    this.externalId,
    this.firstName,
    this.lastName,
    this.includesFirstName = false,
    this.includesLastName = false,
    this.clearAnonymousId = false,
  });

  final String? email;
  final String? externalId;
  final String? firstName;
  final String? lastName;
  final bool includesFirstName;
  final bool includesLastName;
  final bool clearAnonymousId;
}

class ClientApp {
  const ClientApp({this.name, this.description, this.icon});

  final String? name;
  final String? description;
  final String? icon;
}

class DeliveryConfig {
  const DeliveryConfig({
    this.environment,
    this.app,
    this.android,
    this.ios,
    this.web,
  });

  final ClientEnvironment? environment;
  final ClientApp? app;
  final Map<String, Object?>? android;
  final Map<String, Object?>? ios;
  final Map<String, Object?>? web;

  static const empty = DeliveryConfig();
}

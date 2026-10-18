import 'errors.dart';
import 'models.dart';
import 'subscriber.dart';

abstract class Logger {
  void debug(String message, Map<String, String> context);

  void info(String message, Map<String, String> context);

  void warn(String message, Map<String, String> context);

  void error(String message, Map<String, String> context);
}

class SilentLogger implements Logger {
  const SilentLogger();

  @override
  void debug(String message, Map<String, String> context) {}

  @override
  void info(String message, Map<String, String> context) {}

  @override
  void warn(String message, Map<String, String> context) {}

  @override
  void error(String message, Map<String, String> context) {}
}

abstract class KeyValueStore {
  Future<String?> getItem(String key);

  Future<void> setItem(String key, String value);

  Future<void> removeItem(String key);
}

abstract class PushPort {
  PushProvider get provider;

  bool get allowMissingToken;

  Future<PermissionStatus> permissionStatus();

  Future<PermissionStatus> requestPermission();

  Future<String?> token();

  Future<String?> registrationError() async => null;
}

abstract class DevicePort {
  Future<DeviceProfile> profile();

  Future<String?> applicationId();

  void copy(String value);

  Future<bool> get isSimulator async => false;
}

class NotifiableSnapshot {
  const NotifiableSnapshot({
    required this.ready,
    required this.permission,
    this.subscriber,
    this.clientConfig,
    this.devIndicator,
    this.diagnostics,
    this.deepLinks,
    this.error,
  });

  static const initial = NotifiableSnapshot(
    ready: false,
    permission: PermissionStatus.notDetermined,
  );

  final bool ready;
  final PermissionStatus permission;
  final Subscriber? subscriber;
  final DeliveryConfig? clientConfig;
  final DevIndicatorChoice? devIndicator;
  final DiagnosticsChoice? diagnostics;
  final List<DeepLink>? deepLinks;
  final NotifiableError? error;

  NotifiableSnapshot copy({
    bool? ready,
    PermissionStatus? permission,
    Object? subscriber = _keep,
    Object? clientConfig = _keep,
    Object? devIndicator = _keep,
    Object? diagnostics = _keep,
    Object? deepLinks = _keep,
    Object? error = _keep,
  }) {
    return NotifiableSnapshot(
      ready: ready ?? this.ready,
      permission: permission ?? this.permission,
      subscriber: identical(subscriber, _keep) ? this.subscriber : subscriber as Subscriber?,
      clientConfig: identical(clientConfig, _keep)
          ? this.clientConfig
          : clientConfig as DeliveryConfig?,
      devIndicator: identical(devIndicator, _keep)
          ? this.devIndicator
          : devIndicator as DevIndicatorChoice?,
      diagnostics: identical(diagnostics, _keep)
          ? this.diagnostics
          : diagnostics as DiagnosticsChoice?,
      deepLinks: identical(deepLinks, _keep) ? this.deepLinks : deepLinks as List<DeepLink>?,
      error: identical(error, _keep) ? this.error : error as NotifiableError?,
    );
  }
}

const Object _keep = Object();

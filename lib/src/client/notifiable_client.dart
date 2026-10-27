import 'package:flutter/foundation.dart';

import '../domain/environment.dart';
import '../domain/errors.dart';
import '../domain/inbox.dart';
import '../domain/locale.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import '../domain/subscriber.dart';
import '../internal/storage.dart';
import '../platform/flutter_platform.dart';
import '../transport/http_client.dart';
import '../transport/sdk_api.dart';

const Object _platform = Object();

class NotifiableClient extends ChangeNotifier {
  NotifiableClient({
    required String publicKey,
    Logger? logger,
    Object? push = _platform,
    KeyValueStore? storage,
    Object? device = _platform,
    this.deepLinks,
    this.onDeepLink,
    HttpTransport? transport,
  }) : publicKey = publicKey.trim(),
       logger = logger ?? const SilentLogger() {
    if (this.publicKey.isEmpty) {
      throw NotifiableError(
        NotifiableErrorCode.invalidConfig,
        'publicKey is required',
      );
    }

    final resolvedDevice = identical(device, _platform)
        ? FlutterDevicePort()
        : device as DevicePort?;

    if (resolvedDevice == null) {
      throw NotifiableError(
        NotifiableErrorCode.invalidConfig,
        'Notifiable could not read this device.',
      );
    }

    final resolvedPush = identical(push, _platform)
        ? FlutterPushPort()
        : push as PushPort?;
    this.push = resolvedPush;
    this.device = resolvedDevice;
    _storage = storage ?? SharedPreferencesStorage();
    _api = SdkApi(
      HttpClient(
        baseUrl: notifiableApiUrl,
        publicKey: this.publicKey,
        transport: transport ?? const IoHttpTransport(),
      ),
    );
    logger?.debug('Notifiable client created', {
      'hasPush': resolvedPush == null ? 'false' : 'true',
    });
  }

  final String publicKey;
  final Logger logger;
  final List<DeepLink>? deepLinks;
  final void Function(String url)? onDeepLink;
  late final PushPort? push;
  late final DevicePort device;

  NotifiableSnapshot _snapshot = NotifiableSnapshot.initial;
  NotifiableSnapshot get snapshot => _snapshot;

  late final SdkApi _api;
  late final KeyValueStore _storage;
  StoredSession? _session;
  DiagnosticsChoice? _diagnosticsChoice;
  final List<_PendingDiagnostic> _diagnosticQueue = [];
  final Set<String> _diagnosticSeen = {};
  bool _diagnosticFlushing = false;
  Future<void> _tail = Future<void>.value();

  Future<void> start() {
    return _enqueue(() => _performStart());
  }

  Future<PermissionStatus> requestPermission() {
    return _enqueue(() async {
      await _performStart();
      return _performRequestPermission();
    });
  }

  Future<Subscriber> identify({
    String? email,
    String? externalId,
    String? firstName,
    String? lastName,
  }) {
    return _enqueue(() async {
      await _performStart();
      return _performIdentify(
        email: email,
        externalId: externalId,
        firstName: firstName,
        lastName: lastName,
      );
    });
  }

  Future<void> setDevIndicator({required bool enabled}) async {
    final choice = enabled ? DevIndicatorChoice.enabled : DevIndicatorChoice.disabled;
    await saveChoice(
      storage: _storage,
      key: devIndicatorKey(publicKey),
      value: choice.value,
    );
    _commit(devIndicator: choice);
  }

  Future<void> setDiagnostics({required bool enabled}) async {
    final choice = enabled ? DiagnosticsChoice.enabled : DiagnosticsChoice.disabled;
    await saveChoice(
      storage: _storage,
      key: diagnosticsKey(publicKey),
      value: choice.value,
    );
    _diagnosticsChoice = choice;
    _commit(diagnostics: choice);

    if (!enabled) {
      _diagnosticQueue.clear();
    }
  }

  Future<InboxPage> listNotifications({
    required String subscriberId,
    InboxQuery? query,
  }) {
    return _capture(
      () => _api.listNotifications(subscriberId: subscriberId, query: query),
    );
  }

  Future<InboxPage> inbox({InboxQuery? query}) async {
    final subscriberId = _requireSubscriberId();
    return listNotifications(subscriberId: subscriberId, query: query);
  }

  Future<SubscriberNotification> notification(String notificationId) async {
    final subscriberId = _requireSubscriberId();
    return _capture(
      () => _api.getNotification(
        subscriberId: subscriberId,
        notificationId: notificationId,
      ),
    );
  }

  Future<void> openNotification(String notificationId) async {
    final subscriberId = _requireSubscriberId();
    return _capture(
      () => _api.openNotification(
        subscriberId: subscriberId,
        notificationId: notificationId,
      ),
    );
  }

  Future<void> clickDelivery(String deliveryId) {
    return _capture(() => _api.clickDelivery(deliveryId));
  }

  Future<RecordedEvent> track(String name, {Map<String, EventProperty>? properties}) async {
    final subscriberId = _requireSubscriberId();
    return _capture(
      () => _api.trackEvent(
        subscriberId: subscriberId,
        name: name,
        properties: properties,
      ),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final previous = _tail;
    final result = previous.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<void> _performStart() async {
    if (_snapshot.ready) {
      return;
    }

    await _guard(() async {
      final existing = await loadSession(storage: _storage, publicKey: publicKey);
      final session =
          existing ??
          StoredSession(deviceId: createId(), subscriberId: null, pushToken: null, anonymousId: null);

      if (existing == null) {
        await saveSession(storage: _storage, publicKey: publicKey, session: session);
      }

      _session = session;
      final devIndicator = await loadChoice(
        _storage,
        devIndicatorKey(publicKey),
        DevIndicatorChoice.parse,
      );
      final diagnostics = await loadChoice(
        _storage,
        diagnosticsKey(publicKey),
        DiagnosticsChoice.parse,
      );
      _diagnosticsChoice = diagnostics;
      final clientConfig = await _api.getClientConfig();
      _commit(clientConfig: clientConfig, devIndicator: devIndicator, diagnostics: diagnostics);
      await _syncDevice(prompted: false);
      await _saveDeepLinks();
      await _promptIfRequested();
    });
  }

  Future<void> _promptIfRequested() async {
    if (_snapshot.subscriber?.promptPermission != true || push == null) {
      return;
    }

    logger.info('Permission prompt requested', const {});
    // Dashboard prompts must clear even when a token cannot be created.
    await _performRequestPermission(requireToken: false);
  }

  Future<PermissionStatus> _performRequestPermission({bool requireToken = true}) {
    return _guard(() async {
      final current = push;

      if (current == null) {
        throw NotifiableError(
          NotifiableErrorCode.invalidConfig,
          'push is required to request permission.',
        );
      }

      final permission = await current.requestPermission();
      await _syncDevice(
        prompted: true,
        permission: permission,
        requireToken: requireToken && permission == PermissionStatus.granted,
      );
      return _snapshot.permission;
    });
  }

  Future<Subscriber> _performIdentify({
    String? email,
    String? externalId,
    String? firstName,
    String? lastName,
  }) {
    return _guard(() async {
      final session = _requireSession();
      final subscriberId = session.subscriberId;

      if (subscriberId == null) {
        throw NotifiableError(
          NotifiableErrorCode.subscriberNotFound,
          'The subscriber is not registered yet.',
        );
      }

      final identity = _identityFrom(
        email: email,
        externalId: externalId,
        firstName: firstName,
        lastName: lastName,
      );
      final subscriber = await _api.updateSubscriber(
        subscriberId: subscriberId,
        identity: identity,
      );
      final next = StoredSession(
        deviceId: session.deviceId,
        subscriberId: subscriber.id,
        pushToken: session.pushToken,
        anonymousId: subscriber.anonymousId,
      );
      await saveSession(storage: _storage, publicKey: publicKey, session: next);
      _session = next;
      _commit(subscriber: subscriber, error: null);
      logger.info('Subscriber identified', {'subscriberId': subscriber.id});
      return subscriber;
    });
  }

  Future<void> _syncDevice({
    required bool prompted,
    PermissionStatus? permission,
    bool requireToken = false,
  }) async {
    var session = _requireSession();

    if (session.subscriberId == null && session.anonymousId == null) {
      session = StoredSession(
        deviceId: session.deviceId,
        subscriberId: session.subscriberId,
        pushToken: session.pushToken,
        anonymousId: createId(),
      );
      await saveSession(storage: _storage, publicKey: publicKey, session: session);
      _session = session;
    }

    final profile = await device.profile();
    final current = permission ?? await _currentPermission();
    final token = await _tokenFor(current, requireToken: requireToken);
    final savedPermission = token == null && current == PermissionStatus.granted
        ? PermissionStatus.notDetermined
        : current;
    final place = localeParts(profile.locale);
    final subscriber = await _api.saveSubscriber(
      SubscriberWrite(
        deviceId: session.deviceId,
        platform: profile.platform,
        permission: savedPermission,
        provider: token?.provider,
        token: token?.token,
        anonymousId: session.subscriberId == null ? session.anonymousId : null,
        prompted: prompted ? true : null,
        osVersion: profile.osVersion,
        locale: profile.locale,
        timezone: profile.timezone,
        model: profile.model,
        manufacturer: profile.manufacturer,
        appVersion: profile.appVersion,
        ip: profile.ip,
        language: place.language,
        countryCode: place.countryCode,
        sdkVersion: notifiableSdkVersion,
      ),
    );
    final next = StoredSession(
      deviceId: session.deviceId,
      subscriberId: subscriber.id,
      pushToken: token?.token,
      anonymousId: subscriber.anonymousId,
    );
    await saveSession(storage: _storage, publicKey: publicKey, session: next);
    _session = next;
    _commit(
      ready: true,
      permission: savedPermission,
      subscriber: subscriber,
      error: null,
    );
    logger.info('Subscriber saved', {
      'subscriberId': subscriber.id,
      'permission': savedPermission.value,
    });
  }

  Future<PermissionStatus> _currentPermission() async {
    final current = push;

    if (current == null) {
      return PermissionStatus.notDetermined;
    }

    return current.permissionStatus();
  }

  Future<({String token, PushProvider provider})?> _tokenFor(
    PermissionStatus permission, {
    bool requireToken = false,
  }) async {
    if (permission != PermissionStatus.granted) {
      return null;
    }

    final current = push;

    if (current == null) {
      throw NotifiableError(
        NotifiableErrorCode.missingToken,
        'Push permission is granted, but no push port is configured.',
      );
    }

    final token = (await current.token())?.trim() ?? '';

    if (token.isEmpty) {
      if (current.allowMissingToken && !requireToken) {
        return null;
      }

      final detail = await current.registrationError();
      throw NotifiableError(
        NotifiableErrorCode.missingToken,
        detail ?? 'Push permission is granted, but no device token was returned.',
      );
    }

    return (token: token, provider: current.provider);
  }

  Future<void> _saveDeepLinks() async {
    final links = deepLinks;

    if (links == null) {
      return;
    }

    final saved = await _api.saveDeepLinks(links);
    _commit(deepLinks: saved);
    logger.info('Deep links saved', {'count': '${saved.length}'});
  }

  StoredSession _requireSession() {
    final session = _session;

    if (session == null) {
      throw NotifiableError(
        NotifiableErrorCode.subscriberNotFound,
        'The subscriber is not registered yet.',
      );
    }

    return session;
  }

  String _requireSubscriberId() {
    final subscriberId = _requireSession().subscriberId;

    if (subscriberId == null) {
      throw NotifiableError(
        NotifiableErrorCode.subscriberNotFound,
        'The subscriber is not registered yet.',
      );
    }

    return subscriberId;
  }

  Future<T> _guard<T>(Future<T> Function() task) async {
    try {
      return await task();
    } catch (error, stack) {
      _report(error, stack);
      final wrapped = asNotifiableError(error);
      _commit(error: wrapped);
      throw wrapped;
    }
  }

  Future<T> _capture<T>(Future<T> Function() task) async {
    try {
      return await task();
    } catch (error, stack) {
      _report(error, stack);
      throw asNotifiableError(error);
    }
  }

  bool get _diagnosticsOpen {
    return _snapshot.clientConfig?.environment == ClientEnvironment.development &&
        _diagnosticsChoice != DiagnosticsChoice.disabled;
  }

  void _report(Object error, StackTrace stack) {
    if (!_diagnosticsOpen) {
      return;
    }

    final described = describeCrash(error, stack);
    final anchor = described.frames.where(
      (frame) => frame.file.contains('package:notifiable/'),
    );
    final fingerprint = crashFingerprint(
      type: described.type,
      message: described.message,
      frames: anchor.isEmpty ? described.frames : [anchor.first],
    );

    if (_diagnosticSeen.contains(fingerprint)) {
      return;
    }

    _diagnosticSeen.add(fingerprint);
    _diagnosticQueue.add(
      _PendingDiagnostic(
        id: createUlid(),
        occurredAt: DateTime.now().toUtc().toIso8601String(),
        type: described.type,
        message: described.message,
        frames: described.frames,
        subscriberId: diagnosticSubscriberId(_session?.subscriberId),
      ),
    );

    if (_diagnosticQueue.length > 20) {
      _diagnosticQueue.removeAt(0);
    }

    _flushDiagnostics();
  }

  Future<void> _flushDiagnostics() async {
    if (_diagnosticFlushing || _diagnosticQueue.isEmpty) {
      return;
    }

    _diagnosticFlushing = true;

    try {
      while (_diagnosticQueue.isNotEmpty) {
        if (!_diagnosticsOpen) {
          _diagnosticQueue.clear();
          return;
        }

        final batch = _diagnosticQueue.take(20).toList();
        _diagnosticQueue.removeRange(0, batch.length);
        final profile = await device.profile();

        if (!_diagnosticsOpen) {
          return;
        }

        await _api.reportDiagnostics([
          for (final item in batch)
            diagnosticItem(
              id: item.id,
              sdkVersion: notifiableSdkVersion,
              platform: profile.platform,
              occurredAt: item.occurredAt,
              errorType: item.type,
              errorMessage: item.message,
              frames: item.frames,
              subscriberId: item.subscriberId,
            ),
        ]);
      }
    } catch (_) {
      return;
    } finally {
      _diagnosticFlushing = false;
    }
  }

  void _commit({
    bool? ready,
    PermissionStatus? permission,
    Object? subscriber = _keep,
    Object? clientConfig = _keep,
    Object? devIndicator = _keep,
    Object? diagnostics = _keep,
    Object? deepLinks = _keep,
    Object? error = _keep,
  }) {
    _snapshot = _snapshot.copy(
      ready: ready,
      permission: permission,
      subscriber: subscriber,
      clientConfig: clientConfig,
      devIndicator: devIndicator,
      diagnostics: diagnostics,
      deepLinks: deepLinks,
      error: error,
    );
    notifyListeners();
  }
}

class _PendingDiagnostic {
  const _PendingDiagnostic({
    required this.id,
    required this.occurredAt,
    required this.type,
    required this.message,
    required this.frames,
    required this.subscriberId,
  });

  final String id;
  final String occurredAt;
  final String type;
  final String message;
  final List<DiagnosticFrame> frames;
  final String? subscriberId;
}

const Object _keep = Object();

SubscriberIdentity _identityFrom({
  String? email,
  String? externalId,
  String? firstName,
  String? lastName,
}) {
  String? trimmedEmail;
  String? trimmedExternalId;

  if (email != null) {
    trimmedEmail = email.trim();

    if (trimmedEmail.isEmpty) {
      throw NotifiableError(
        NotifiableErrorCode.invalidConfig,
        'email cannot be blank.',
      );
    }
  }

  if (externalId != null) {
    trimmedExternalId = externalId.trim();

    if (trimmedExternalId.isEmpty) {
      throw NotifiableError(
        NotifiableErrorCode.invalidConfig,
        'externalId cannot be blank.',
      );
    }
  }

  final includesFirstName = firstName != null;
  final includesLastName = lastName != null;

  if (trimmedEmail == null &&
      trimmedExternalId == null &&
      !includesFirstName &&
      !includesLastName) {
    throw NotifiableError(
      NotifiableErrorCode.invalidConfig,
      'identify requires an email, externalId, firstName, or lastName.',
    );
  }

  return SubscriberIdentity(
    email: trimmedEmail,
    externalId: trimmedExternalId,
    firstName: firstName,
    lastName: lastName,
    includesFirstName: includesFirstName,
    includesLastName: includesLastName,
    clearAnonymousId: trimmedEmail != null || trimmedExternalId != null,
  );
}

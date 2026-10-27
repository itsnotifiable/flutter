import '../domain/environment.dart';
import '../domain/errors.dart';
import '../domain/inbox.dart';
import '../domain/models.dart';
import '../domain/subscriber.dart';
import 'http_client.dart';

class SdkApi {
  SdkApi(this.http);

  final HttpClient http;

  Future<DeliveryConfig> getClientConfig() async {
    final data = await http.request(method: 'GET', path: '/v1/sdk/client-config');
    return parseDeliveryConfig(data);
  }

  Future<Subscriber> saveSubscriber(SubscriberWrite write) async {
    final data = await http.request(
      method: 'POST',
      path: '/v1/sdk/subscribers',
      body: subscriberBody(write),
    );
    return parseSubscriber(data);
  }

  Future<Subscriber> updateSubscriber({
    required String subscriberId,
    required SubscriberIdentity identity,
  }) async {
    final data = await http.request(
      method: 'PATCH',
      path: '/v1/sdk/subscribers/${_path(subscriberId)}',
      body: identityBody(identity),
    );
    return parseSubscriber(data);
  }

  Future<InboxPage> listNotifications({
    required String subscriberId,
    InboxQuery? query,
  }) async {
    final data = await http.request(
      method: 'GET',
      path: inboxPath(subscriberId, query),
    );
    return parseInboxPage(data);
  }

  Future<SubscriberNotification> getNotification({
    required String subscriberId,
    required String notificationId,
  }) async {
    final data = await http.request(
      method: 'GET',
      path:
          '/v1/sdk/subscribers/${_path(subscriberId)}/notifications/${_path(notificationId)}',
    );
    final notification = parseNotification(data);

    if (notification == null) {
      throw NotifiableError(
        NotifiableErrorCode.network,
        'The notification response was invalid.',
      );
    }

    return notification;
  }

  Future<void> openNotification({
    required String subscriberId,
    required String notificationId,
  }) async {
    await http.request(
      method: 'POST',
      path:
          '/v1/sdk/subscribers/${_path(subscriberId)}/notifications/${_path(notificationId)}/open',
    );
  }

  Future<void> clickDelivery(String deliveryId) async {
    await http.request(
      method: 'POST',
      path: '/v1/sdk/deliveries/${_path(deliveryId)}/click',
    );
  }

  Future<RecordedEvent> trackEvent({
    required String subscriberId,
    required String name,
    Map<String, EventProperty>? properties,
  }) async {
    final body = <String, Object?>{
      'name': name,
      'subscriber_id': subscriberId,
    };

    if (properties != null) {
      body['properties'] = properties.map((key, value) => MapEntry(key, value.json));
    }

    final data = await http.request(method: 'POST', path: '/v1/sdk/events', body: body);
    return parseRecordedEvent(data);
  }

  Future<List<DeepLink>> saveDeepLinks(List<DeepLink> links) async {
    final data = await http.request(
      method: 'POST',
      path: '/v1/sdk/deep-links',
      body: {
        'links': [
          for (final link in links) {'path': link.path, 'label': link.label},
        ],
      },
    );
    return parseDeepLinks(data);
  }

  Future<int> reportDiagnostics(List<Map<String, Object?>> items) async {
    final data = await http.request(
      method: 'POST',
      path: '/v1/sdk/diagnostics',
      body: {'items': items},
    );
    return parseAccepted(data);
  }
}

Map<String, Object?> subscriberBody(SubscriberWrite write) {
  final body = <String, Object?>{
    'device_id': write.deviceId,
    'platform': write.platform.value,
    'sdk': notifiableSdkName,
    'permission': write.permission.value,
  };
  _assign(body, 'provider', write.provider?.value);
  _assign(body, 'token', write.token);
  _assign(body, 'anonymous_id', write.anonymousId);

  if (write.prompted == true) {
    body['prompted'] = true;
  }

  _assign(body, 'os_version', write.osVersion);
  _assign(body, 'locale', write.locale);
  _assign(body, 'timezone', write.timezone);
  _assign(body, 'device_model', write.model);
  _assign(body, 'device_manufacturer', write.manufacturer);
  _assign(body, 'device_ip', write.ip);
  _assign(body, 'app_version', write.appVersion);
  _assign(body, 'sdk_version', write.sdkVersion);
  _assign(body, 'language', write.language);
  _assign(body, 'country_code', write.countryCode);
  return body;
}

Map<String, Object?> identityBody(SubscriberIdentity identity) {
  final body = <String, Object?>{};
  _assign(body, 'email', identity.email);
  _assign(body, 'external_id', identity.externalId);

  if (identity.includesFirstName) {
    body['first_name'] = identity.firstName;
  }

  if (identity.includesLastName) {
    body['last_name'] = identity.lastName;
  }

  if (identity.clearAnonymousId) {
    body['anonymous_id'] = null;
  }

  return body;
}

Map<String, Object?> diagnosticItem({
  required String id,
  required String sdkVersion,
  required MobilePlatform platform,
  required String occurredAt,
  required String errorType,
  required String errorMessage,
  required List<DiagnosticFrame> frames,
  String? subscriberId,
}) {
  final body = <String, Object?>{
    'id': id,
    'kind': 'crash',
    'sdk': notifiableSdkName,
    'sdk_version': sdkVersion,
    'platform': platform.value,
    'occurred_at': occurredAt,
    'error': {
      'type': errorType,
      'message': errorMessage,
      'frames': [
        for (final frame in frames)
          {'function': frame.function, 'file': frame.file, 'line': frame.line},
      ],
    },
  };

  if (subscriberId != null) {
    body['subscriber_id'] = subscriberId;
  }

  return body;
}

void _assign(Map<String, Object?> body, String key, String? value) {
  if (value != null) {
    body[key] = value;
  }
}

String inboxPath(String subscriberId, InboxQuery? query) {
  final path = '/v1/sdk/subscribers/${_path(subscriberId)}/notifications';
  final params = <String>[];

  if (query?.page != null) {
    params.add('page=${query!.page}');
  }

  if (query?.opened != null) {
    params.add('opened=${query!.opened! ? 'true' : 'false'}');
  }

  if (params.isEmpty) {
    return path;
  }

  return '$path?${params.join('&')}';
}

String _path(String value) => Uri.encodeComponent(value);

DeliveryConfig parseDeliveryConfig(Object? data) {
  if (data is List) {
    if (data.isEmpty) {
      return DeliveryConfig.empty;
    }

    throw _invalidClientConfig();
  }

  final fields = _object(data);

  if (fields == null) {
    throw _invalidClientConfig();
  }

  return DeliveryConfig(
    environment: ClientEnvironment.parse(_string(fields['environment'])),
    app: _clientApp(fields['app']),
    android: _record(fields['android']),
    ios: _record(fields['ios']),
    web: _record(fields['web']),
  );
}

ClientApp? _clientApp(Object? value) {
  final fields = _object(value);

  if (fields == null) {
    return null;
  }

  return ClientApp(
    name: _text(fields['name']),
    description: _text(fields['description']),
    icon: _text(fields['icon']),
  );
}

NotifiableError _invalidClientConfig() {
  return NotifiableError(
    NotifiableErrorCode.network,
    'The client configuration response was invalid.',
  );
}

Subscriber parseSubscriber(Object? data) {
  final fields = _object(data);
  final id = fields == null ? null : _string(fields['id']);
  final environment = fields == null ? null : _string(fields['environment']);
  final platform = DevicePlatform.parse(fields == null ? null : _string(fields['platform']));
  final permission = PermissionStatus.parse(
    fields == null ? null : _string(fields['permission']),
  );
  final prompt = fields?['prompt_permission'];

  if (fields == null ||
      id == null ||
      id.isEmpty ||
      environment == null ||
      platform == null ||
      permission == null ||
      prompt is! bool) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The subscriber response was invalid.',
    );
  }

  // Unknown values (including legacy "expo") become null so old sessions load.
  final PushProvider? provider;

  if (!fields.containsKey('provider') || fields['provider'] == null) {
    provider = null;
  } else {
    provider = PushProvider.parse(_string(fields['provider']));
  }

  return Subscriber(
    id: id,
    environment: environment,
    platform: platform,
    permission: permission,
    sdk: _text(fields['sdk']),
    provider: provider,
    deviceId: _text(fields['device_id']),
    externalId: _text(fields['external_id']),
    anonymousId: _text(fields['anonymous_id']),
    promptPermission: prompt,
  );
}

int parseAccepted(Object? data) {
  final fields = _object(data);
  final accepted = fields?['accepted'];

  if (accepted is int) {
    return accepted;
  }

  if (accepted is double && accepted == accepted.roundToDouble()) {
    return accepted.toInt();
  }

  throw NotifiableError(
    NotifiableErrorCode.network,
    'The diagnostics response was invalid.',
  );
}

RecordedEvent parseRecordedEvent(Object? data) {
  final fields = _object(data);
  final id = fields == null ? null : _text(fields['id']);
  final name = fields == null ? null : _string(fields['name']);
  final subscriberId = fields == null ? null : _string(fields['subscriber_id']);

  if (id == null || name == null || subscriberId == null) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The event response was invalid.',
    );
  }

  return RecordedEvent(id: id, name: name, subscriberId: subscriberId);
}

List<DeepLink> parseDeepLinks(Object? data) {
  final fields = _object(data);
  final links = fields?['links'];

  if (links is! List) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The deep link response was invalid.',
    );
  }

  return [
    for (final entry in links)
      if (_deepLink(entry) case final link?) link,
  ];
}

DeepLink? _deepLink(Object? entry) {
  final fields = _object(entry);
  final path = fields == null ? null : _text(fields['path']);
  final label = fields == null ? null : _text(fields['label']);

  if (path == null || label == null) {
    return null;
  }

  return DeepLink(path: path, label: label);
}

InboxPage parseInboxPage(Object? data) {
  final fields = _object(data);
  final notifications = fields?['notifications'];
  final page = _int(fields?['page']);
  final perPage = _int(fields?['per_page']);
  final total = _int(fields?['total']);

  if (notifications is! List || page == null || perPage == null || total == null) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The notification list was invalid.',
    );
  }

  return InboxPage(
    notifications: [
      for (final item in notifications)
        if (parseNotification(item) case final notification?) notification,
    ],
    page: page,
    perPage: perPage,
    total: total,
  );
}

SubscriberNotification? parseNotification(Object? value) {
  final fields = _object(value);
  final id = fields == null ? null : _text(fields['id']);
  final title = fields == null ? null : _string(fields['title']);
  final body = fields == null ? null : _string(fields['body']);
  final opened = fields?['opened'];
  final createdAt = fields == null ? null : _string(fields['created_at']);

  if (id == null || title == null || body == null || opened is! bool || createdAt == null) {
    return null;
  }

  final alert = fields!['alert'];
  return SubscriberNotification(
    id: id,
    title: title,
    body: body,
    url: _text(fields['url']),
    imageUrl: _text(fields['image_url']),
    data: _record(fields['data']),
    alert: alert is bool ? alert : true,
    status: _text(fields['status']),
    opened: opened,
    openedAt: _text(fields['opened_at']),
    createdAt: createdAt,
    deliveryId: _text(fields['delivery_id']),
  );
}

Map<String, Object?>? _object(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return null;
}

Map<String, Object?>? _record(Object? value) => _object(value);

String? _string(Object? value) => value is String ? value : null;

String? _text(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }

  return value;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is double && value == value.roundToDouble()) {
    return value.toInt();
  }

  return null;
}

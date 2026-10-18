const devNotificationFreshMs = 8000;
const _clockSkewMs = 2000;

class SubscriberNotification {
  const SubscriberNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.alert,
    required this.opened,
    required this.createdAt,
    this.url,
    this.imageUrl,
    this.data,
    this.status,
    this.openedAt,
    this.deliveryId,
  });

  final String id;
  final String title;
  final String body;
  final String? url;
  final String? imageUrl;
  final Map<String, Object?>? data;
  final bool alert;
  final String? status;
  final bool opened;
  final String? openedAt;
  final String createdAt;
  final String? deliveryId;
}

class InboxQuery {
  const InboxQuery({this.page, this.opened});

  final int? page;
  final bool? opened;
}

class InboxPage {
  const InboxPage({
    required this.notifications,
    required this.page,
    required this.perPage,
    required this.total,
  });

  final List<SubscriberNotification> notifications;
  final int page;
  final int perPage;
  final int total;
}

String? notificationDeliveryId(SubscriberNotification notification) {
  final deliveryId = notification.deliveryId;

  if (deliveryId != null && deliveryId.isNotEmpty) {
    return deliveryId;
  }

  return _opt(notification.url);
}

String? _opt(String? url) {
  if (url == null || url.isEmpty) {
    return null;
  }

  final direct = Uri.tryParse(url);
  final parsed = direct ??
      Uri.tryParse(
        'https://notifiable.invalid${url.startsWith('/') ? '' : '/'}$url',
      );
  final value = parsed?.queryParameters['opt'];

  if (value == null || value.isEmpty) {
    return null;
  }

  return value;
}

List<SubscriberNotification> selectFreshNotifications(
  List<SubscriberNotification> notifications, {
  required int nowMs,
  required Set<String> seen,
}) {
  return notifications.where((notification) {
    if (notification.opened || !notification.alert || seen.contains(notification.id)) {
      return false;
    }

    final created = DateTime.tryParse(notification.createdAt)?.millisecondsSinceEpoch;

    if (created == null) {
      return false;
    }

    final age = nowMs - created;
    return age >= -_clockSkewMs && age <= devNotificationFreshMs;
  }).toList();
}

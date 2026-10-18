import 'dart:async';

import 'package:flutter/material.dart';

import '../client/notifiable_client.dart';
import '../domain/errors.dart';
import '../domain/inbox.dart';
import '../domain/subscriber.dart';
import 'scope.dart';

class DevToasts extends StatefulWidget {
  const DevToasts({super.key});

  @override
  State<DevToasts> createState() => _DevToastsState();
}

class _DevToastsState extends State<DevToasts> {
  NotifiableClient? _client;
  var _identity = '';
  var _generation = 0;
  SubscriberNotification? _current;
  final List<SubscriberNotification> _queue = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = NotifiableScope.of(context);
    _client = client;
    final environment = client.snapshot.clientConfig?.environment?.value ?? '';
    final identity =
        '${client.snapshot.subscriber?.id}|${client.snapshot.permission.value}|$environment';

    if (identity == _identity) {
      return;
    }

    _identity = identity;
    _generation += 1;
    unawaited(_poll(client, _generation));
  }

  Future<void> _poll(NotifiableClient client, int generation) async {
    if (client.snapshot.clientConfig?.environment != ClientEnvironment.development) {
      return;
    }

    if (client.snapshot.permission != PermissionStatus.granted) {
      return;
    }

    final subscriberId = client.snapshot.subscriber?.id;

    if (subscriberId == null) {
      return;
    }

    var delay = const Duration(seconds: 5);
    final seen = <String>{};
    final order = <String>[];

    while (mounted && generation == _generation) {
      final state = WidgetsBinding.instance.lifecycleState;

      if (state != null && state != AppLifecycleState.resumed) {
        await Future<void>.delayed(delay);
        continue;
      }

      debugPrint('[Notifiable] Polling notifications for $subscriberId');

      try {
        final page = await client.listNotifications(
          subscriberId: subscriberId,
          query: const InboxQuery(page: 1, opened: false),
        );

        if (!mounted ||
            generation != _generation ||
            client.snapshot.subscriber?.id != subscriberId) {
          return;
        }

        delay = const Duration(seconds: 5);
        final fresh = selectFreshNotifications(
          page.notifications,
          nowMs: DateTime.now().millisecondsSinceEpoch,
          seen: seen,
        );

        for (final notification in fresh) {
          _remember(notification.id, seen, order);
          final title = notification.title.isEmpty ? notification.id : notification.title;
          debugPrint('[Notifiable] New notification: $title');
        }

        if (fresh.isNotEmpty && mounted) {
          setState(() {
            _queue.addAll(fresh);
            _current ??= _queue.removeAt(0);
          });
        }
      } on NotifiableError catch (error) {
        if (error.code == NotifiableErrorCode.invalidPublicKey ||
            error.code == NotifiableErrorCode.subscriberNotFound) {
          return;
        }

        if (error.code == NotifiableErrorCode.rateLimited) {
          final doubled = delay * 2;
          delay = doubled > const Duration(seconds: 30)
              ? const Duration(seconds: 30)
              : doubled;
        }
      } catch (_) {
        if (!mounted || generation != _generation) {
          return;
        }
      }

      await Future<void>.delayed(delay);
    }
  }

  void _advance() {
    if (!mounted) {
      return;
    }

    setState(() {
      _current = _queue.isEmpty ? null : _queue.removeAt(0);
    });
  }

  void _open(SubscriberNotification notification) {
    final client = _client;
    final deliveryId = notificationDeliveryId(notification);

    if (client != null && deliveryId != null) {
      unawaited(_ignore(client.clickDelivery(deliveryId)));
    }

    final url = notification.url;

    if (url != null && client != null) {
      debugPrint('[Notifiable] Opening $url');
      client.onDeepLink?.call(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final current = _current;

    if (client == null ||
        client.snapshot.clientConfig?.environment != ClientEnvironment.development ||
        current == null) {
      return const SizedBox.shrink();
    }

    return _ToastCard(
      key: ValueKey(current.id),
      notification: current,
      iconUrl: client.snapshot.clientConfig?.app?.icon,
      appName: client.snapshot.clientConfig?.app?.name,
      onOpen: () => _open(current),
      onDismiss: _advance,
      onShown: () {
        unawaited(_ignore(client.openNotification(current.id)));
      },
    );
  }
}

Future<void> _ignore(Future<void> action) async {
  try {
    await action;
  } catch (_) {}
}

void _remember(String id, Set<String> seen, List<String> order) {
  if (!seen.add(id)) {
    return;
  }

  order.add(id);

  if (order.length > 50) {
    seen.remove(order.removeAt(0));
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.notification,
    required this.iconUrl,
    required this.appName,
    required this.onOpen,
    required this.onDismiss,
    required this.onShown,
  });

  final SubscriberNotification notification;
  final String? iconUrl;
  final String? appName;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onShown;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> {
  var _visible = false;
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.onShown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
    unawaited(_dismissLater());
  }

  Future<void> _dismissLater() async {
    await Future<void>.delayed(const Duration(milliseconds: 4500));

    if (mounted) {
      _leave();
    }
  }

  void _leave() {
    if (_leaving) {
      return;
    }

    _leaving = true;
    setState(() => _visible = false);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 280)).then((_) {
        if (mounted) {
          widget.onDismiss();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.notification.title.isEmpty
        ? 'Notification'
        : widget.notification.title;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _leave,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: const ColoredBox(color: Color(0x47000000)),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          top: 8,
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, -1.2),
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            child: Material(
              color: Colors.white,
              elevation: 8,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  widget.onOpen();
                  _leave();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      _BannerIcon(url: widget.iconUrl, name: widget.appName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF141414),
                                    ),
                                  ),
                                ),
                                const Text(
                                  'now',
                                  style: TextStyle(fontSize: 12, color: Color(0x61000000)),
                                ),
                              ],
                            ),
                            if (widget.notification.body.isNotEmpty)
                              Text(
                                widget.notification.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0x80000000)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerIcon extends StatelessWidget {
  const _BannerIcon({required this.url, required this.name});

  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final icon = url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 40,
        height: 40,
        child: icon == null
            ? _fallback()
            : Image.network(
                icon,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() {
    final letter = name?.trim().isNotEmpty == true ? name!.trim()[0].toUpperCase() : 'N';
    return ColoredBox(
      color: const Color(0xFFEBEBEB),
      child: Center(
        child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

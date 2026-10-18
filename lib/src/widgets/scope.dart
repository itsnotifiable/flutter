import 'package:flutter/widgets.dart';

import '../client/notifiable_client.dart';
import '../domain/errors.dart';

class NotifiableScope extends InheritedNotifier<NotifiableClient> {
  const NotifiableScope({
    super.key,
    required NotifiableClient client,
    required super.child,
  }) : super(notifier: client);

  NotifiableClient get client => notifier!;

  static NotifiableClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NotifiableScope>();

    if (scope == null) {
      throw NotifiableError(
        NotifiableErrorCode.missingProvider,
        'Notifiable.of() was called outside of a Notifiable widget.',
      );
    }

    return scope.client;
  }
}

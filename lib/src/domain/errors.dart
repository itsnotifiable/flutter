enum NotifiableErrorCode {
  invalidConfig('invalid_config'),
  missingProvider('missing_provider'),
  notImplemented('not_implemented'),
  invalidPublicKey('invalid_public_key'),
  network('network'),
  validationFailed('validation_failed'),
  subscriberNotFound('subscriber_not_found'),
  subscriberLimit('subscriber_limit'),
  rateLimited('rate_limited'),
  missingToken('missing_token'),
  missingStorage('missing_storage');

  const NotifiableErrorCode(this.value);

  final String value;
}

class NotifiableError implements Exception {
  NotifiableError(this.code, [String? message]) : message = message ?? code.value;

  final NotifiableErrorCode code;
  final String message;

  @override
  bool operator ==(Object other) {
    return other is NotifiableError &&
        other.code == code &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'NotifiableError(${code.value}): $message';
}

NotifiableError asNotifiableError(Object error) {
  if (error is NotifiableError) {
    return error;
  }

  return NotifiableError(NotifiableErrorCode.network, error.toString());
}

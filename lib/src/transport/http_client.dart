import 'dart:convert';
import 'dart:io' as io;

import '../domain/errors.dart';

const _apiErrorCodes = <String, NotifiableErrorCode>{
  'INVALID_PUBLIC_KEY': NotifiableErrorCode.invalidPublicKey,
  'VALIDATION_FAILED': NotifiableErrorCode.validationFailed,
  'SUBSCRIBER_NOT_FOUND': NotifiableErrorCode.subscriberNotFound,
  'SUBSCRIBER_LIMIT_REACHED': NotifiableErrorCode.subscriberLimit,
  'RATE_LIMIT_EXCEEDED': NotifiableErrorCode.rateLimited,
};

class HttpResult {
  const HttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract class HttpTransport {
  Future<HttpResult> send({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    String? body,
  });
}

class IoHttpTransport implements HttpTransport {
  const IoHttpTransport();

  @override
  Future<HttpResult> send({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    String? body,
  }) async {
    final client = io.HttpClient();

    try {
      final request = await client.openUrl(method, url);
      headers.forEach(request.headers.set);

      if (body != null) {
        request.add(utf8.encode(body));
      }

      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (collected, chunk) => collected..addAll(chunk),
      );
      return HttpResult(statusCode: response.statusCode, body: utf8.decode(bytes));
    } on NotifiableError {
      rethrow;
    } catch (error) {
      throw NotifiableError(NotifiableErrorCode.network, error.toString());
    } finally {
      client.close(force: true);
    }
  }
}

class HttpClient {
  HttpClient({
    required this.baseUrl,
    required this.publicKey,
    required this.transport,
  });

  final String baseUrl;
  final String publicKey;
  final HttpTransport transport;

  Future<Object?> request({
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Notifiable-Key': publicKey,
    };
    String? encoded;

    if (body != null) {
      headers['Content-Type'] = 'application/json';
      encoded = jsonEncode(body);
    }

    final HttpResult response;

    try {
      response = await transport.send(
        method: method,
        url: _join(baseUrl, path),
        headers: headers,
        body: encoded,
      );
    } on NotifiableError {
      rethrow;
    } catch (error) {
      throw NotifiableError(NotifiableErrorCode.network, error.toString());
    }

    return readEnvelope(response.body);
  }
}

Object? readEnvelope(String raw) {
  final Object? payload;

  try {
    payload = jsonDecode(raw);
  } catch (_) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The response was not JSON.',
    );
  }

  if (payload is! Map) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The response envelope was invalid.',
    );
  }

  final status = payload['status'];

  if (status is! String) {
    throw NotifiableError(
      NotifiableErrorCode.network,
      'The response envelope was invalid.',
    );
  }

  if (status == 'success') {
    return payload['data'];
  }

  final code = payload['code'];
  final mapped = code is String
      ? _apiErrorCodes[code] ?? NotifiableErrorCode.network
      : NotifiableErrorCode.network;
  final fallback = payload['message'] is String
      ? payload['message'] as String
      : 'The request failed.';
  throw NotifiableError(mapped, _errorMessage(payload['error'], fallback));
}

String _errorMessage(Object? error, String fallback) {
  if (error is! Map) {
    return fallback;
  }

  final details = error['details'];

  if (details is! List) {
    return fallback;
  }

  final messages = <String>[];

  for (final item in details) {
    if (item is Map && item['message'] is String) {
      messages.add(item['message'] as String);
    }
  }

  return messages.isEmpty ? fallback : messages.join(' ');
}

Uri _join(String baseUrl, String path) {
  final root = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final suffix = path.startsWith('/') ? path : '/$path';
  return Uri.parse('$root$suffix');
}

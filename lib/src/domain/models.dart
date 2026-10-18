import 'errors.dart';

class DeepLink {
  const DeepLink({required this.path, required this.label});

  final String path;
  final String label;

  @override
  bool operator ==(Object other) {
    return other is DeepLink && other.path == path && other.label == label;
  }

  @override
  int get hashCode => Object.hash(path, label);
}

class EventProperty {
  const EventProperty.string(String value) : _value = value, isNull = false;

  const EventProperty.number(num value) : _value = value, isNull = false;

  const EventProperty.bool(bool value) : _value = value, isNull = false;

  const EventProperty.nullValue() : _value = null, isNull = true;

  final Object? _value;
  final bool isNull;

  Object? get json => isNull ? null : _value;
}

class RecordedEvent {
  const RecordedEvent({
    required this.id,
    required this.name,
    required this.subscriberId,
  });

  final String id;
  final String name;
  final String subscriberId;
}

enum DevIndicatorChoice {
  enabled('enabled'),
  disabled('disabled');

  const DevIndicatorChoice(this.value);

  final String value;

  static DevIndicatorChoice? parse(String? raw) {
    return _parse(values, raw);
  }
}

enum DiagnosticsChoice {
  enabled('enabled'),
  disabled('disabled');

  const DiagnosticsChoice(this.value);

  final String value;

  static DiagnosticsChoice? parse(String? raw) {
    return _parse(values, raw);
  }
}

T? _parse<T extends Enum>(List<T> values, String? raw) {
  if (raw == null) {
    return null;
  }

  for (final value in values) {
    if (value is DevIndicatorChoice && value.value == raw) {
      return value as T;
    }

    if (value is DiagnosticsChoice && value.value == raw) {
      return value as T;
    }
  }

  return null;
}

class DiagnosticFrame {
  const DiagnosticFrame({
    required this.function,
    required this.file,
    required this.line,
  });

  final String function;
  final String file;
  final int line;
}

class DescribedCrash {
  const DescribedCrash({
    required this.type,
    required this.message,
    required this.frames,
  });

  final String type;
  final String message;
  final List<DiagnosticFrame> frames;
}

enum PackageCheck { match, mismatch }

PackageCheck? packageCheck({String? configured, String? applicationId}) {
  if (applicationId == null || applicationId.isEmpty) {
    return null;
  }

  if (configured == null || configured != applicationId) {
    return PackageCheck.mismatch;
  }

  return PackageCheck.match;
}

DescribedCrash describeCrash(Object error, [StackTrace? stack]) {
  final frames = parseFrames(stack?.toString() ?? '').take(20).toList();

  if (error is NotifiableError) {
    return DescribedCrash(
      type: limit('NotifiableError.${error.code.value}', 200),
      message: limit(error.message, 2000),
      frames: frames,
    );
  }

  final name = error.runtimeType.toString();
  return DescribedCrash(
    type: limit(name.isEmpty ? 'Error' : name, 200),
    message: limit(error.toString(), 2000),
    frames: frames,
  );
}

String crashFingerprint({
  required String type,
  required String message,
  required List<DiagnosticFrame> frames,
}) {
  final site = frames.isEmpty
      ? ''
      : '${frames.first.function}|${frames.first.file}|${frames.first.line}';
  return '$type|$message|$site';
}

final _uuid = RegExp(
  r'^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$',
  caseSensitive: false,
);

String? diagnosticSubscriberId(String? subscriberId) {
  if (subscriberId == null || !_uuid.hasMatch(subscriberId)) {
    return null;
  }

  return subscriberId;
}

List<DiagnosticFrame> parseFrames(String stack) {
  final frames = <DiagnosticFrame>[];

  for (final line in stack.split('\n')) {
    final frame = _parseFrame(line.trim());

    if (frame != null) {
      frames.add(frame);
    }
  }

  return frames;
}

final _dartFrame = RegExp(r'^#\d+\s+(.+?)\s+\((.+):(\d+):\d+\)$');
final _jsFrame = RegExp(
  r'^\s*at\s+(?:async\s+)?(.*?)\s+\((?:address at\s+)?(.+):(\d+):\d+\)$',
);

DiagnosticFrame? _parseFrame(String line) {
  if (line.isEmpty) {
    return null;
  }

  for (final pattern in [_dartFrame, _jsFrame]) {
    final match = pattern.firstMatch(line);

    if (match != null) {
      return _makeFrame(match.group(1) ?? '', match.group(2) ?? '', match.group(3) ?? '');
    }
  }

  return null;
}

DiagnosticFrame? _makeFrame(String function, String file, String line) {
  final lineNumber = int.tryParse(line);

  if (lineNumber == null || lineNumber < 1) {
    return null;
  }

  final fileName = limit(file.trim(), 500);

  if (fileName.isEmpty) {
    return null;
  }

  final name = function.trim();
  return DiagnosticFrame(
    function: limit(name.isEmpty ? 'anonymous' : name, 200),
    file: fileName,
    line: lineNumber,
  );
}

String limit(String value, int max) {
  if (value.length <= max) {
    return value;
  }

  return value.substring(0, max);
}

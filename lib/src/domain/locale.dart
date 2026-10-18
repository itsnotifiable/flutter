class LocaleParts {
  const LocaleParts({this.language, this.countryCode});

  final String? language;
  final String? countryCode;
}

final _language = RegExp(r'^[A-Za-z]{2,8}$');
final _region = RegExp(r'^[A-Za-z]{2}$');
final _ipv4 = RegExp(
  r'^(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
);

LocaleParts localeParts(String? locale) {
  if (locale == null) {
    return const LocaleParts();
  }

  final tags = locale.split(RegExp(r'[-_]'));
  final language = tags.isEmpty || !_language.hasMatch(tags.first)
      ? null
      : tags.first.toLowerCase();
  String? countryCode;

  for (final tag in tags.skip(1)) {
    if (_region.hasMatch(tag)) {
      countryCode = tag.toUpperCase();
    }
  }

  return LocaleParts(language: language, countryCode: countryCode);
}

String? deviceAddress(String? value) {
  if (value == null) {
    return null;
  }

  final address = value.trim();

  if (!_ipv4.hasMatch(address) ||
      address == '0.0.0.0' ||
      address.startsWith('127.')) {
    return null;
  }

  return address;
}

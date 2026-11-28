final _serverOrigin = RegExp(
  r'^https?://[^/?#\\\s@\x00-\x1f\x7f]+/?$',
  caseSensitive: false,
);

Uri parseServerAddress(String input) {
  const invalid = FormatException('Enter an HTTP or HTTPS server origin.');
  final address = input.trim();
  if (!_serverOrigin.hasMatch(address)) throw invalid;
  final uri = Uri.tryParse(address);
  if (uri == null || uri.host.isEmpty || uri.port < 1 || uri.port > 65535) {
    throw invalid;
  }
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
}

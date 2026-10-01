import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

const _maxPairingBytes = 16384;
final _random = Random.secure();
String _token(int bytes) => base64UrlEncode(
  List<int>.generate(bytes, (_) => _random.nextInt(256)),
).replaceAll('=', '');

/// Deliberately excludes DNS, public addresses and IPv6 in this first version.
/// A scanned QR must never turn the phone into an arbitrary Internet client.
bool isPairingLanAddress(String host) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null || ip.type != InternetAddressType.IPv4 || ip.address != host) {
    return false;
  }
  final b = ip.rawAddress;
  if (b.join('.') != host) return false;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

class PairingTicket {
  final String host;
  final int port;
  final String session;
  final String key;
  final DateTime expires;

  const PairingTicket({
    required this.host,
    required this.port,
    required this.session,
    required this.key,
    required this.expires,
  });

  String get link => Uri(
    scheme: 'lumen-pair',
    host: 'v1',
    queryParameters: {
      'host': host,
      'port': '$port',
      'session': session,
      'key': key,
      'expires': '${expires.millisecondsSinceEpoch}',
    },
  ).toString();

  factory PairingTicket.parse(
    String link, {
    bool allowLoopbackForTesting = false,
  }) {
    try {
      if (link.length > 2048) throw const FormatException();
      final uri = Uri.parse(link.trim());
      final p = uri.queryParameters;
      final host = p['host']!;
      final port = int.parse(p['port']!);
      final session = p['session']!;
      final key = p['key']!;
      final expires = DateTime.fromMillisecondsSinceEpoch(
        int.parse(p['expires']!),
      );
      if (uri.scheme != 'lumen-pair' ||
          uri.host != 'v1' ||
          uri.path.isNotEmpty ||
          uri.fragment.isNotEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          p.length != 5 ||
          uri.queryParametersAll.values.any((v) => v.length != 1) ||
          (!isPairingLanAddress(host) &&
              !(allowLoopbackForTesting && host == '127.0.0.1')) ||
          port < 1024 ||
          port > 65535 ||
          !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(session) ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(key) ||
          base64Url.decode(base64Url.normalize(key)).length != 32 ||
          !expires.isAfter(DateTime.now()) ||
          expires.difference(DateTime.now()) > const Duration(minutes: 5)) {
        throw const FormatException();
      }
      return PairingTicket(
        host: host,
        port: port,
        session: session,
        key: key,
        expires: expires,
      );
    } catch (_) {
      // Never include the input, which contains the pairing secret.
      throw const FormatException(
        'Invalid or expired Lumen pairing QR. Scan a new QR on the TV.',
      );
    }
  }

  @override
  String toString() => 'PairingTicket(redacted)';
}

class _PairingCipher {
  final PairingTicket ticket;
  final _aes = AesGcm.with256bits();
  _PairingCipher(this.ticket);
  SecretKey get _key =>
      SecretKey(base64Url.decode(base64Url.normalize(ticket.key)));
  List<int> _aad(String direction) =>
      utf8.encode('lumen-pair/v1/${ticket.session}/$direction');

  Future<List<int>> encrypt(
    Map<String, dynamic> value,
    String direction,
  ) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: _key,
      nonce: _aes.newNonce(),
      aad: _aad(direction),
    );
    return utf8.encode(
      jsonEncode({
        'nonce': base64Encode(box.nonce),
        'data': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }

  Future<Map<String, dynamic>> decrypt(
    List<int> bytes,
    String direction,
  ) async {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final nonce = base64Decode(j['nonce'] as String);
    final mac = base64Decode(j['mac'] as String);
    if (nonce.length != 12 || mac.length != 16) throw const FormatException();
    final plain = await _aes.decrypt(
      SecretBox(base64Decode(j['data'] as String), nonce: nonce, mac: Mac(mac)),
      secretKey: _key,
      aad: _aad(direction),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }
}

Future<List<int>> _readBody(Stream<List<int>> stream) async {
  final bytes = <int>[];
  final iterator = StreamIterator(stream);
  final elapsed = Stopwatch()..start();
  try {
    while (await iterator.moveNext().timeout(
      const Duration(seconds: 5) - elapsed.elapsed,
    )) {
      final chunk = iterator.current;
      if (bytes.length + chunk.length > _maxPairingBytes) {
        throw const FormatException();
      }
      bytes.addAll(chunk);
    }
  } finally {
    unawaited(iterator.cancel());
  }
  return bytes;
}

/// Strict wire validation; never trust permissive model deserialization here.
XtreamCredentials pairingCredentials(Map<String, dynamic> j) {
  String field(String key, int max) {
    final v = j[key];
    if (v is! String || v.length > max || v.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Invalid account details.');
    }
    return v;
  }

  final base = field('baseUrl', 2048);
  final user = field('username', 256);
  final pass = field('password', 1024);
  final m3u = j['m3uUrl'] == null ? null : field('m3uUrl', 4096);
  bool url(String v) {
    final u = Uri.tryParse(v);
    return u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty &&
        u.userInfo.isEmpty &&
        u.fragment.isEmpty;
  }

  if (j['demo'] == true ||
      !url(base) ||
      (m3u != null ? !url(m3u) : user.trim().isEmpty || pass.isEmpty)) {
    throw const FormatException(
      'Enter a valid HTTP(S) provider or playlist account.',
    );
  }
  return XtreamCredentials(
    baseUrl: base,
    username: user,
    password: pass,
    m3uUrl: m3u,
  );
}

enum PairingState { waiting, pending, approved, rejected, expired, closed }

/// Owns only an ephemeral local server. It never writes credentials to storage.
class PairingReceiver extends ChangeNotifier {
  final HttpServer _server;
  final PairingTicket ticket;
  late final _cipher = _PairingCipher(ticket);
  late final Timer _expiry;
  final _acknowledged = Completer<void>();
  PairingState state = PairingState.waiting;
  XtreamCredentials? _pending;
  String? _offer;
  String? comparisonCode;
  String? providerHost;
  int _activeRequests = 0;
  int _badRequests = 0;
  bool _closed = false;
  bool _disposed = false;

  PairingReceiver._(this._server, this.ticket) {
    _expiry = Timer(
      ticket.expires.difference(DateTime.now()),
      () => close(expired: true),
    );
    _server.idleTimeout = const Duration(seconds: 5);
    _server.listen(
      (request) => unawaited(_handle(request)),
      onError: (_) => close(),
    );
  }

  static Future<List<String>> localAddresses() async =>
      (await NetworkInterface.list(type: InternetAddressType.IPv4))
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where(isPairingLanAddress)
          .toSet()
          .toList();

  static Future<PairingReceiver> start(
    String host, {
    Duration lifetime = const Duration(minutes: 3),
    bool allowLoopbackForTesting = false,
  }) async {
    if (!isPairingLanAddress(host) &&
        !(allowLoopbackForTesting && host == '127.0.0.1')) {
      throw const FormatException('Connect the TV to your home network first.');
    }
    final server = await HttpServer.bind(InternetAddress(host), 0);
    final ticket = PairingTicket(
      host: host,
      port: server.port,
      session: _token(16),
      key: _token(32),
      expires: DateTime.now().add(lifetime),
    );
    return PairingReceiver._(server, ticket);
  }

  Future<void> _handle(HttpRequest request) async {
    if (_closed || _activeRequests >= 4 || _badRequests >= 20) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    _activeRequests++;
    request.response.persistentConnection = false;
    bool acknowledge = false;
    try {
      if (request.method != 'POST' ||
          request.uri.path != '/pair/${ticket.session}' ||
          request.uri.hasQuery ||
          request.headers.contentType?.mimeType != 'application/json' ||
          request.headers.value('origin') != null ||
          request.contentLength > _maxPairingBytes) {
        throw const FormatException();
      }
      final msg = await _cipher.decrypt(
        await _readBody(request).timeout(const Duration(seconds: 6)),
        'phone',
      );
      final id = msg['id'];
      final offer = msg['offer'];
      if (_closed ||
          !DateTime.now().isBefore(ticket.expires) ||
          id is! String ||
          offer is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id) ||
          !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(offer)) {
        throw const FormatException();
      }
      if (msg['action'] == 'offer' && state == PairingState.waiting) {
        final credentials = pairingCredentials(
          Map<String, dynamic>.from(msg['credentials'] as Map),
        );
        _pending = credentials;
        _offer = offer;
        providerHost = Uri.parse(
          credentials.m3uUrl ?? credentials.baseUrl,
        ).host;
        comparisonCode = (_random.nextInt(900000) + 100000).toString();
        state = PairingState.pending;
        notifyListeners();
      } else if ((msg['action'] != 'status' && msg['action'] != 'offer') ||
          offer != _offer) {
        throw const FormatException();
      }
      // The request challenge prevents replaying an older authenticated status.
      final responseState = state;
      final bytes = await _cipher.encrypt({
        'id': id,
        'offer': offer,
        'state': responseState.name,
        'code': comparisonCode,
      }, 'tv');
      if (_closed) throw const FormatException();
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.add(bytes);
      acknowledge =
          responseState == PairingState.approved && msg['action'] == 'status';
    } catch (_) {
      _badRequests++;
      request.response.statusCode = HttpStatus.badRequest;
    } finally {
      try {
        await request.response.close();
      } catch (_) {
        /* Disconnected phone. */
      }
      _activeRequests--;
      if (acknowledge && !_acknowledged.isCompleted) _acknowledged.complete();
    }
  }

  Future<XtreamCredentials?> approve() async {
    if (state != PairingState.pending || _closed) return null;
    final credentials = _pending;
    _pending = null;
    state = PairingState.approved;
    notifyListeners();
    // Give the phone a chance to receive approval before the login route closes.
    await _acknowledged.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    return _closed ? null : credentials;
  }

  void reject() {
    if (state != PairingState.pending || _closed) return;
    _pending = null;
    state = PairingState.rejected;
    notifyListeners();
  }

  void close({bool expired = false}) {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    _pending = null;
    state = expired ? PairingState.expired : PairingState.closed;
    unawaited(_server.close(force: true));
    if (!_acknowledged.isCompleted) _acknowledged.complete();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    close();
    super.dispose();
  }
}

class PairingReply {
  final PairingState state;
  final String code;
  const PairingReply(this.state, this.code);
}

class PairingSender {
  final PairingTicket ticket;
  late final _cipher = _PairingCipher(ticket);
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final String _offer = _token(16);
  bool _closed = false;
  PairingSender(this.ticket);

  Future<PairingReply> send(XtreamCredentials credentials) =>
      _exchange('offer', credentials: pairingCredentials(credentials.toJson()));
  Future<PairingReply> status() => _exchange('status');

  Future<PairingReply> _exchange(
    String action, {
    XtreamCredentials? credentials,
  }) async {
    if (_closed || !DateTime.now().isBefore(ticket.expires)) {
      throw const FormatException('Pairing expired. Scan a new QR on the TV.');
    }
    final id = _token(16);
    try {
      return await (() async {
        final body = await _cipher.encrypt({
          'id': id,
          'offer': _offer,
          'action': action,
          if (credentials != null) 'credentials': credentials.toJson(),
        }, 'phone');
        if (body.length > _maxPairingBytes) throw const FormatException();
        final request = await _http.postUrl(
          Uri(
            scheme: 'http',
            host: ticket.host,
            port: ticket.port,
            path: '/pair/${ticket.session}',
          ),
        );
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.add(body);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) throw const FormatException();
        final reply = await _cipher.decrypt(await _readBody(response), 'tv');
        if (_closed ||
            reply['id'] != id ||
            reply['offer'] != _offer ||
            reply['code'] is! String ||
            !RegExp(r'^\d{6}$').hasMatch(reply['code'] as String)) {
          throw const FormatException();
        }
        return PairingReply(
          PairingState.values.byName(reply['state'] as String),
          reply['code'] as String,
        );
      })().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Kill timed-out operations too; they must not deliver a late offer.
      close();
      throw const FormatException(
        'Cannot reach the TV securely. Use the same home network, allow local network access, and scan a new QR. Guest Wi-Fi or a VPN may isolate devices.',
      );
    }
  }

  void close() {
    _closed = true;
    _http.close(force: true);
  }
}

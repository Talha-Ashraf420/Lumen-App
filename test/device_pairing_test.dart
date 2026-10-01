import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/device_pairing.dart';
import 'package:lumen_tv/models.dart';

const account = XtreamCredentials(
  baseUrl: 'https://provider.example',
  username: 'viewer',
  password: 'test-secret',
);
final aes = AesGcm.with256bits();

Future<List<int>> envelope(
  PairingTicket ticket,
  Map<String, dynamic> message, {
  String direction = 'phone',
}) async {
  final box = await aes.encrypt(
    utf8.encode(jsonEncode(message)),
    secretKey: SecretKey(base64Url.decode(base64Url.normalize(ticket.key))),
    nonce: aes.newNonce(),
    aad: utf8.encode('lumen-pair/v1/${ticket.session}/$direction'),
  );
  return utf8.encode(
    jsonEncode({
      'nonce': base64Encode(box.nonce),
      'data': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    }),
  );
}

Future<int> post(
  PairingTicket ticket,
  List<int> bytes, {
  bool origin = false,
}) async {
  final http = HttpClient();
  try {
    final request = await http.postUrl(
      Uri(
        scheme: 'http',
        host: ticket.host,
        port: ticket.port,
        path: '/pair/${ticket.session}',
      ),
    );
    request.headers.contentType = ContentType.json;
    if (origin) request.headers.set('Origin', 'https://untrusted.example');
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    http.close(force: true);
  }
}

void main() {
  Future<PairingReceiver> receiver({
    Duration lifetime = const Duration(minutes: 3),
  }) async {
    final r = await PairingReceiver.start(
      '127.0.0.1',
      allowLoopbackForTesting: true,
      lifetime: lifetime,
    );
    addTearDown(r.dispose);
    return r;
  }

  PairingSender sender(PairingTicket ticket) {
    final s = PairingSender(ticket);
    addTearDown(s.close);
    return s;
  }

  test(
    'QR contains no provider credentials and only accepts literal LAN endpoints',
    () async {
      final r = await receiver();
      final link = r.ticket.link.replaceFirst('127.0.0.1', '192.168.1.22');
      expect(PairingTicket.parse(link).host, '192.168.1.22');
      expect(link, isNot(contains(account.password)));
      expect(link, isNot(contains(account.baseUrl)));
      for (final host in [
        '127.0.0.1',
        '8.8.8.8',
        'example.com',
        '169.254.169.254',
        '::1',
        '192.168.001.2',
      ]) {
        expect(
          () => PairingTicket.parse(link.replaceFirst('192.168.1.22', host)),
          throwsFormatException,
        );
      }
      expect(
        () => PairingTicket.parse('$link&host=10.0.0.1'),
        throwsFormatException,
      );
      expect(
        () => PairingTicket.parse(link.replaceFirst('lumen-pair', 'https')),
        throwsFormatException,
      );
      expect(() => PairingTicket.parse('$link#other'), throwsFormatException);
      expect(r.ticket.toString(), isNot(contains(r.ticket.key)));
    },
  );

  test(
    'encrypted account stays pending until explicit approval; TV and phone agree',
    () async {
      final r = await receiver();
      final s = sender(r.ticket);
      expect(await r.approve(), isNull);
      final reply = await s.send(account);
      expect(reply.state, PairingState.pending);
      expect(reply.code, r.comparisonCode);
      expect(r.providerHost, 'provider.example');
      final approval = r.approve();
      expect((await s.status()).state, PairingState.approved);
      expect((await approval)?.toJson(), account.toJson());
      expect(await r.approve(), isNull);
      // Same offer can be retried idempotently, but never applied twice.
      expect((await s.send(account)).state, PairingState.approved);
      expect(await r.approve(), isNull);
      await expectLater(sender(r.ticket).send(account), throwsFormatException);
    },
  );

  test(
    'reject is terminal and a second phone cannot replace a pending account',
    () async {
      final r = await receiver();
      final first = sender(r.ticket);
      await first.send(account);
      await expectLater(sender(r.ticket).send(account), throwsFormatException);
      r.reject();
      expect((await first.status()).state, PairingState.rejected);
      expect(await r.approve(), isNull);
      expect((await first.send(account)).state, PairingState.rejected);
    },
  );

  test(
    'M3U secrets are encrypted and only its hostname is shown for approval',
    () async {
      final r = await receiver();
      final s = sender(r.ticket);
      const playlist = XtreamCredentials(
        baseUrl: 'https://provider.example/list?token=private',
        username: 'playlist',
        password: '',
        m3uUrl: 'https://provider.example/list?token=private',
      );
      await s.send(playlist);
      expect(r.providerHost, 'provider.example');
      final approval = r.approve();
      await s.status();
      expect((await approval)?.m3uUrl, playlist.m3uUrl);
    },
  );

  test('expiry and close clear offers and prevent delayed approval', () async {
    final r = await receiver(lifetime: const Duration(milliseconds: 150));
    final s = sender(r.ticket);
    await s.send(account);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(r.state, PairingState.expired);
    expect(await r.approve(), isNull);
    await expectLater(s.status(), throwsFormatException);
    final other = await receiver();
    await sender(other.ticket).send(account);
    final approval = other.approve();
    other.close();
    expect(await approval, isNull);
  });

  test(
    'tampering, reflected ciphertext, browser requests and oversized bodies fail closed',
    () async {
      final r = await receiver();
      final msg = {
        'id': 'a' * 22,
        'offer': 'b' * 22,
        'action': 'offer',
        'credentials': account.toJson(),
      };
      final bytes = await envelope(r.ticket, msg);
      expect(utf8.decode(bytes), isNot(contains(account.password)));
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = base64Decode(j['data'] as String)..[0] ^= 1;
      j['data'] = base64Encode(data);
      expect(await post(r.ticket, utf8.encode(jsonEncode(j))), 400);
      expect(
        await post(r.ticket, await envelope(r.ticket, msg, direction: 'tv')),
        400,
      );
      expect(await post(r.ticket, bytes, origin: true), 400);
      expect(await post(r.ticket, List.filled(17000, 65)), 400);
      expect(r.state, PairingState.waiting);
      expect(await post(r.ticket, bytes), 200);
      expect(r.state, PairingState.pending);
    },
  );

  test(
    'invalid credential payload does not poison the pairing session',
    () async {
      final r = await receiver();
      final bytes = await envelope(r.ticket, {
        'id': 'a' * 22,
        'offer': 'b' * 22,
        'action': 'offer',
        'credentials': {...account.toJson(), 'demo': true},
      });
      expect(await post(r.ticket, bytes), 400);
      expect(r.state, PairingState.waiting);
      expect(
        (await sender(r.ticket).send(account)).state,
        PairingState.pending,
      );
      for (final changes in [
        {'baseUrl': 'file:///private/data'},
        {'username': ''},
        {'password': 23},
        {'password': 'x\nother'},
        {'m3uUrl': 'ftp://example.com/list'},
      ]) {
        expect(
          () => pairingCredentials({...account.toJson(), ...changes}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'wrong key cannot create a pending request and errors never reveal secrets',
    () async {
      final r = await receiver();
      final wrong = PairingTicket(
        host: r.ticket.host,
        port: r.ticket.port,
        session: r.ticket.session,
        key: base64UrlEncode(List.filled(32, 0)).replaceAll('=', ''),
        expires: r.ticket.expires,
      );
      await expectLater(
        sender(wrong).send(account),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'safe error',
            isNot(contains(account.password)),
          ),
        ),
      );
      expect(r.state, PairingState.waiting);
    },
  );

  test(
    'phone authenticates responses and rejects replayed status challenges',
    () async {
      final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => fake.close(force: true));
      final ticket = PairingTicket(
        host: '127.0.0.1',
        port: fake.port,
        session: 'a' * 22,
        key: base64UrlEncode(List.filled(32, 1)).replaceAll('=', ''),
        expires: DateTime.now().add(const Duration(minutes: 2)),
      );
      fake.listen((request) async {
        await request.drain<void>();
        request.response.add(
          await envelope(ticket, {
            'id': 'old',
            'offer': 'old',
            'state': 'approved',
            'code': '123456',
          }, direction: 'tv'),
        );
        await request.response.close();
      });
      await expectLater(sender(ticket).send(account), throwsFormatException);
    },
  );
}

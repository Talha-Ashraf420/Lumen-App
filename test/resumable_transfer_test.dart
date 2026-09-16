import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/resumable_transfer.dart';

void main() {
  late Directory temp;
  late HttpServer server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumen-transfer-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  test('early EOF retries from the saved byte offset', () async {
    const body = 'hello world!';
    final requests = <String?>[];
    var count = 0;
    server.listen((request) async {
      requests.add(request.headers.value(HttpHeaders.rangeHeader));
      if (count++ == 0) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-4/12',
        );
        request.response.write(body.substring(0, 5));
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 5-11/12',
        );
        request.response.headers.contentLength = 7;
        request.response.write(body.substring(5));
        await request.response.close();
      }
    });

    final file = File('${temp.path}/movie.mp4');
    final result = await downloadResumable(
      uri: Uri.parse('http://${server.address.host}:${server.port}/movie'),
      file: file,
      isInterrupted: () => false,
      retryDelay: Duration.zero,
    );

    expect(await file.readAsString(), body);
    expect(result.received, 12);
    expect(requests, [null, 'bytes=5-']);
  });

  test('incorrect Content-Range is discarded before another retry', () async {
    const body = 'abcdefghijkl';
    final requests = <String?>[];
    var count = 0;
    server.listen((request) async {
      requests.add(request.headers.value(HttpHeaders.rangeHeader));
      if (count++ == 0) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-4/12',
        );
        request.response.write(body.substring(0, 5));
        await request.response.close();
      } else if (count == 2) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-6/12',
        );
        request.response.write(body.substring(0, 7));
        await request.response.close();
      } else {
        request.response.headers.contentLength = body.length;
        request.response.write(body);
        await request.response.close();
      }
    });

    final file = File('${temp.path}/movie.mp4');
    await downloadResumable(
      uri: Uri.parse('http://${server.address.host}:${server.port}/movie'),
      file: file,
      isInterrupted: () => false,
      retryDelay: Duration.zero,
    );

    expect(await file.readAsString(), body);
    expect(requests, [null, 'bytes=5-', null]);
  });

  test('permanent provider denial is not retried', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });

    await expectLater(
      downloadResumable(
        uri: Uri.parse('http://${server.address.host}:${server.port}/movie'),
        file: File('${temp.path}/movie.mp4'),
        isInterrupted: () => false,
        retryDelay: Duration.zero,
      ),
      throwsA(isA<TransferPermanentFailure>()),
    );
    expect(requests, 1);
  });

  test(
    'transient provider error retries without losing partial bytes',
    () async {
      final requests = <String?>[];
      var count = 0;
      server.listen((request) async {
        requests.add(request.headers.value(HttpHeaders.rangeHeader));
        if (count++ == 0) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
        } else {
          request.response.write('working');
        }
        await request.response.close();
      });

      final file = File('${temp.path}/movie.mp4');
      await downloadResumable(
        uri: Uri.parse('http://${server.address.host}:${server.port}/movie'),
        file: file,
        isInterrupted: () => false,
        retryDelay: Duration.zero,
      );
      expect(await file.readAsString(), 'working');
      expect(requests, [null, null]);
    },
  );

  test(
    'already complete partial is accepted when provider returns 416',
    () async {
      final file = File('${temp.path}/movie.mp4');
      await file.writeAsString('complete');
      server.listen((request) async {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=8-');
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */8',
        );
        await request.response.close();
      });

      final result = await downloadResumable(
        uri: Uri.parse('http://${server.address.host}:${server.port}/movie'),
        file: file,
        isInterrupted: () => false,
        retryDelay: Duration.zero,
      );
      expect(result, (received: 8, total: 8));
      expect(await file.readAsString(), 'complete');
    },
  );
}

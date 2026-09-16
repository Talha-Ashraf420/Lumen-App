import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class TransferInterrupted implements Exception {}

class TransferPermanentFailure implements Exception {
  const TransferPermanentFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Streams a direct media file without treating a single slow response as a
/// failed download. Every retry reopens the partial file at its actual byte
/// length. A provider that sends an incorrect Content-Range is never appended
/// to an existing video; the partial is discarded and fetched again.
Future<({int received, int total})> downloadResumable({
  required Uri uri,
  required File file,
  required bool Function() isInterrupted,
  void Function(http.Client client)? onClient,
  void Function(int received, int total)? onProgress,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration idleTimeout = const Duration(seconds: 45),
  Duration retryDelay = const Duration(seconds: 1),
  int maxAttempts = 8,
}) async {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const TransferPermanentFailure('The download URL is invalid.');
  }
  if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
  await file.parent.create(recursive: true);
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    if (isInterrupted()) throw TransferInterrupted();
    final client = http.Client();
    onClient?.call(client);
    IOSink? sink;
    try {
      final start = await file.exists() ? await file.length() : 0;
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20';
      if (start > 0) request.headers['Range'] = 'bytes=$start-';
      final response = await client.send(request).timeout(connectTimeout);
      final code = response.statusCode;
      if (code == HttpStatus.requestedRangeNotSatisfiable && start > 0) {
        final reportedTotal = RegExp(
          r'^bytes \*/(\d+)$',
        ).firstMatch(response.headers['content-range'] ?? '');
        if (int.tryParse(reportedTotal?.group(1) ?? '') == start) {
          onProgress?.call(start, start);
          return (received: start, total: start);
        }
        // The remote file changed (or the partial exceeds its length).
        // Discard it before retrying, rather than looping on the same range.
        await file.delete();
        throw const HttpException('Saved byte range is no longer available.');
      }
      if (code != 200 && code != 206) {
        if (code != 408 && code != 425 && code != 429 && code < 500) {
          throw TransferPermanentFailure('Provider returned HTTP $code.');
        }
        throw HttpException('Provider returned HTTP $code.');
      }
      final range = code == 206
          ? RegExp(
              r'^bytes (\d+)-(\d+)/(\d+|\*)$',
            ).firstMatch(response.headers['content-range'] ?? '')
          : null;
      if (code == 206 &&
          (range == null || int.parse(range.group(1)!) != start)) {
        // A corrupt range is more dangerous than a restart from byte zero.
        if (await file.exists()) await file.delete();
        throw const HttpException('Invalid provider byte range.');
      }
      final append = start > 0 && code == 206;
      final receivedAtStart = append ? start : 0;
      final rangeTotal = int.tryParse(range?.group(3) ?? '');
      final length = response.contentLength ?? 0;
      final total = rangeTotal ?? (length > 0 ? receivedAtStart + length : 0);
      var received = receivedAtStart;
      sink = file.openWrite(mode: append ? FileMode.append : FileMode.write);
      onProgress?.call(received, total);
      await for (final chunk in response.stream.timeout(idleTimeout)) {
        if (isInterrupted()) throw TransferInterrupted();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (isInterrupted()) throw TransferInterrupted();
      if (total > 0 && received != total) {
        throw const HttpException('Connection ended before file completed.');
      }
      return (received: received, total: total);
    } on TransferInterrupted {
      rethrow;
    } on TransferPermanentFailure {
      rethrow;
    } on FileSystemException catch (error) {
      throw TransferPermanentFailure('Unable to save the download: $error');
    } catch (error) {
      if (isInterrupted()) throw TransferInterrupted();
      lastError = error;
    } finally {
      try {
        await sink?.flush();
      } catch (_) {}
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
    }
    if (attempt == maxAttempts) break;
    final waitMs = (retryDelay.inMilliseconds * (1 << (attempt - 1))).clamp(
      0,
      30000,
    );
    var waited = 0;
    while (waited < waitMs) {
      if (isInterrupted()) throw TransferInterrupted();
      final step = (waitMs - waited).clamp(0, 250);
      await Future<void>.delayed(Duration(milliseconds: step));
      waited += step;
    }
  }
  throw HttpException(
    'Connection interrupted after $maxAttempts attempts: $lastError',
  );
}

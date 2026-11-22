import 'dart:async';
import 'dart:io';

/// Downloads a big file in a way that survives a bad connection:
///  * it writes to a ".part" file and, after any drop, continues from the last
///    byte it already has (HTTP Range), never from zero;
///  * it notices a silent stall (no data for 30 s) and reconnects by itself;
///  * it keeps the partial file if the app is closed, so the next start resumes.
class ResumableDownload {
  ResumableDownload({required this.url, required this.part, required this.expectedBytes});

  final String url;
  final File part;
  final int expectedBytes; // rough size, used when the server does not say
  bool cancelled = false;

  static const _stall = Duration(seconds: 30);
  static const maxAttempts = 80;

  int get have => part.existsSync() ? part.lengthSync() : 0;

  /// Returns when the whole file is on disk. [onProgress] gets bytes done and
  /// total; [onNote] gets a plain-words status such as "Connection dropped".
  Future<void> run({
    required void Function(int done, int total) onProgress,
    required void Function(String note) onNote,
  }) async {
    var attempt = 0;
    while (true) {
      if (cancelled) throw 'Download cancelled.';
      try {
        final done = await _once(onProgress);
        if (done) return;
      } catch (e) {
        if (cancelled) throw 'Download cancelled.';
        attempt++;
        if (attempt > maxAttempts) {
          throw 'The connection keeps dropping ($e).';
        }
        final wait = Duration(seconds: attempt < 5 ? 2 * attempt : 10);
        onNote('Connection dropped. Continuing from ${(have / 1e6).round()} MB in '
            '${wait.inSeconds}s… (retry $attempt)');
        await Future<void>.delayed(wait);
      }
    }
  }

  /// One connection attempt. Returns true when the file is complete.
  Future<bool> _once(void Function(int done, int total) onProgress) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'TravelDesk/2';
    IOSink? sink;
    try {
      var offset = have;
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      req.maxRedirects = 8;
      if (offset > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      final res = await req.close().timeout(const Duration(seconds: 30));

      var total = expectedBytes;
      var append = false;
      if (res.statusCode == 206) {
        final cr = res.headers.value(HttpHeaders.contentRangeHeader); // bytes a-b/total
        final t = cr == null ? null : int.tryParse(cr.split('/').last);
        if (t != null && t > 0) total = t;
        append = true;
      } else if (res.statusCode == 200) {
        if (res.contentLength > 0) total = res.contentLength;
        offset = 0; // the server ignored Range: start over
      } else if (res.statusCode == 416) {
        await res.drain<void>();
        return offset > 0; // we already have everything
      } else {
        await res.drain<void>();
        throw HttpException('server answered ${res.statusCode}');
      }

      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var done = offset;
      onProgress(done, total);
      await for (final chunk in res.timeout(_stall)) {
        if (cancelled) throw 'Download cancelled.';
        sink.add(chunk);
        done += chunk.length;
        onProgress(done, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total > 0 && res.contentLength > 0 && done < total - 1024) {
        throw 'the connection closed early at ${(done / 1e6).round()} MB';
      }
      return true;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }
}

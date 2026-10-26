import 'package:http/http.dart' as http;

import '../source_adapter.dart';
import 'source_prober.dart';

/// Minimal HTTP probe: one range request, short timeout, latency in the result.
class HttpStreamProber {
  HttpStreamProber({
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<ProbeResult> probe(PlayableStream stream) async {
    final watch = Stopwatch()..start();
    try {
      final response = await _client.get(
        Uri.parse(stream.url),
        headers: {...stream.headers, 'Range': 'bytes=0-0'},
      ).timeout(timeout);
      watch.stop();
      final status = response.statusCode;
      final reachable = status < 400 || status == 416;
      return ProbeResult(
        url: stream.url,
        reachable: reachable,
        latency: watch.elapsed,
        error: reachable ? null : 'HTTP $status',
      );
    } catch (error) {
      watch.stop();
      return ProbeResult(
        url: stream.url,
        reachable: false,
        latency: watch.elapsed,
        error: error,
      );
    }
  }

  void close() => _client.close();
}

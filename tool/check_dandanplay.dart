// Exercises the real DandanplayClient (not a MockClient) against the live open
// danmaku API, so the signature scheme and the response parsing are checked with
// the same code the player uses. Credentials come from the environment and are
// never printed in full.
//
//   $env:PRAXINO_DANDAN_APP_ID = '<AppId>'
//   $env:PRAXINO_DANDAN_APP_SECRET = '<AppSecret>'
//   dart run tool/check_dandanplay.dart "孤独摇滚"
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:praxino/core/danmaku/dandanplay_provider.dart';

Future<void> main(List<String> args) async {
  final appId = Platform.environment['PRAXINO_DANDAN_APP_ID'] ?? '';
  final secret = Platform.environment['PRAXINO_DANDAN_APP_SECRET'] ?? '';
  if (appId.isEmpty || secret.isEmpty) {
    stderr.writeln(
      'Set PRAXINO_DANDAN_APP_ID / PRAXINO_DANDAN_APP_SECRET first.',
    );
    exit(2);
  }
  final anime = args.isEmpty ? '孤独摇滚' : args.first;
  final client = DandanplayClient(
    appId: appId,
    appSecret: secret,
    client: http.Client(),
  );
  try {
    print('search anime=$anime');
    final episodes = await client.searchEpisodes(anime: anime);
    print('episodes=${episodes.length}');
    for (final episode in episodes.take(3)) {
      print('  ${episode.episodeId} ${episode.animeTitle} / ${episode.episodeTitle}');
    }
    if (episodes.isEmpty) {
      stderr.writeln('search returned no episodes');
      exitCode = 1;
      return;
    }
    final first = episodes.first.episodeId;
    final comments = await client.comments(first);
    print('comments=${comments.length} episode=$first');
    for (final comment in comments.take(3)) {
      print('  ${comment.time.inMilliseconds}ms ${comment.text}');
    }
    print('dandanplay_ok');
  } on DandanplayException catch (error) {
    stderr.writeln('dandanplay_error $error');
    exitCode = 1;
  } finally {
    client.close();
  }
}

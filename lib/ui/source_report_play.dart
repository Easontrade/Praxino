import 'package:flutter/material.dart';

import '../core/settings/settings_store.dart';
import '../core/sources/source_report.dart';
import 'media_detail_page.dart';
import 'player_page.dart';

/// Plays a source-ranking row. A resolved direct stream opens the player
/// immediately; a player page falls back to the detail page with auto-play so
/// the WebView sniffer can find the real URL.
Future<void> playReportEntry(
  BuildContext context,
  SettingsStore settings,
  SourceReportEntry entry,
) async {
  final stream = entry.stream;
  if (stream != null && !SourceReport.looksLikeLandingPage(stream.url)) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(settings: settings, streams: [stream]),
    ));
    return;
  }
  final adapter = entry.adapter;
  final media = entry.media;
  if (adapter != null && media != null) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaDetailPage(
        adapter: adapter,
        media: media,
        settings: settings,
        autoPlay: true,
      ),
    ));
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('这个源没有可播放地址')));
}

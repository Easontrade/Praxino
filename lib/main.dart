import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/library/local_files.dart';
import 'core/settings/settings_store.dart';
import 'ui/home_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final settings = await SettingsStore.load();
  // `praxino.exe <file>` — used by "Open with" and file associations.
  final initial = args.where((a) => isVideoFile(a) || a.contains('://'));
  runApp(PraxinoApp(settings: settings, initialSource: initial.firstOrNull));
}

class PraxinoApp extends StatelessWidget {
  const PraxinoApp({super.key, required this.settings, this.initialSource});

  final SettingsStore settings;
  final String? initialSource;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Praxino',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFE8A33D),
        fontFamily: 'Microsoft YaHei UI',
      ),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE8A33D),
        fontFamily: 'Microsoft YaHei UI',
      ),
      home: HomePage(settings: settings, initialSource: initialSource),
    );
  }
}

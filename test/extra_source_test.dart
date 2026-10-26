import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:praxino/core/sources/extra_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('extra sources round-trip through json', () {
    const source = ExtraSource(
      id: 'stremio-1',
      name: 'Demo',
      type: ExtraSourceType.stremio,
      location: 'https://example.test',
    );
    final restored = ExtraSource.tryFromJson(source.toJson());
    expect(restored!.name, 'Demo');
    expect(restored.type, ExtraSourceType.stremio);
  });

  test('settings persist extra sources', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    await settings.saveExtraSources(const [
      ExtraSource(
        id: 'script-1',
        name: 'Script',
        type: ExtraSourceType.script,
        location: 'function search() { return []; }',
      ),
    ]);
    expect(settings.extraSources.single.type, ExtraSourceType.script);
  });
}

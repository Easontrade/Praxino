import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stores dandanplay credentials', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    expect(settings.dandanplayAppId, isEmpty);
    await settings.setDandanplayCredentials('app', 'secret');
    expect(settings.dandanplayAppId, 'app');
    expect(settings.dandanplayAppSecret, 'secret');

    await settings.setInterpolationScriptPath(r'C:\Tools\vs\rife.vpy');
    expect(settings.interpolationScriptPath, r'C:\Tools\vs\rife.vpy');
  });
}

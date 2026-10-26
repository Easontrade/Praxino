import 'enhance_settings.dart';

/// Holds the settings that must be restored after a hold-to-compare gesture.
///
/// Kept separate from the player so the transition logic is unit-testable.
class CompareState {
  EnhanceSettings? _saved;

  bool get active => _saved != null;

  /// Starts comparing; returns the "off" settings to show, or null if already
  /// comparing.
  EnhanceSettings? begin(EnhanceSettings current) {
    if (active) return null;
    _saved = current;
    return const EnhanceSettings();
  }

  /// Ends comparing and returns the settings to restore.
  EnhanceSettings? end() {
    final saved = _saved;
    _saved = null;
    return saved;
  }

  /// A settings change while comparing updates what will be restored.
  void noteSettingsChange(EnhanceSettings settings) {
    if (active) _saved = settings;
  }
}

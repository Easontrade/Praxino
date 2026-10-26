/// Player shortcuts as a Flutter-free model.
///
/// The UI turns a [KeyChord] into a `SingleActivator`; `lib/core` must not
/// import Flutter, so keys are plain lowercase names here. See
/// docs/ROADMAP.md (card M1-7) and docs/ARCHITECTURE.md section 4.
library;

import 'dart:convert';

/// Everything the player window can trigger.
enum PlayerAction {
  upscaleOff,
  upscaleFast,
  upscaleBalanced,
  upscaleQuality,
  toggleEnhance,
  subtitleDelayDown,
  subtitleDelayUp,
  speedDown,
  speedUp,
  screenshot,
  togglePlaylist,
}

/// One key and the modifiers held with it.
///
/// [key] is a lowercase, Flutter-independent name: `0`..`9`, `a`..`z`, or a
/// named key such as `space`, `bracketleft`, `arrowup`, `f1`. Use [tryParse]
/// to build a chord from recorded or stored input, and [label] for its
/// canonical `ctrl+alt+shift+key` form.
class KeyChord {
  const KeyChord({
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });

  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;

  /// Keys that have no single-character form. The names are the familiar
  /// Flutter ones (`space`, `bracketleft`, `arrowup`, `f1`), lowercased and
  /// without separators, so the UI can map them with a lookup table.
  static const Set<String> _namedKeys = {
    'space',
    'enter',
    'tab',
    'escape',
    'backspace',
    'delete',
    'insert',
    'home',
    'end',
    'pageup',
    'pagedown',
    'arrowup',
    'arrowdown',
    'arrowleft',
    'arrowright',
    'bracketleft',
    'bracketright',
    'backquote',
    'minus',
    'equal',
    'semicolon',
    'quote',
    'comma',
    'period',
    'slash',
    'backslash',
    'capslock',
    'numlock',
    'scrolllock',
    'printscreen',
    'pause',
    'contextmenu',
    'mediaplaypause',
    'mediastop',
    'medianexttrack',
    'mediaprevioustrack',
    'volumeup',
    'volumedown',
    'volumemute',
  };

  static final RegExp _character = RegExp(r'^[a-z0-9]$');
  static final RegExp _functionKey = RegExp(r'^f([1-9]|1[0-9]|2[0-4])$');

  /// Parses `ctrl+1`, `shift+space`, `bracketleft`.
  ///
  /// Input is trimmed and lowercased. Returns null for empty input, an
  /// unknown or repeated modifier, or an unknown key.
  static KeyChord? tryParse(String raw) {
    final parts = [
      for (final part in raw.trim().toLowerCase().split('+')) part.trim(),
    ];
    final key = parts.last;
    if (!_isKnownKey(key)) return null;
    var ctrl = false;
    var alt = false;
    var shift = false;
    for (final modifier in parts.take(parts.length - 1)) {
      if (modifier == 'ctrl') {
        if (ctrl) return null;
        ctrl = true;
      } else if (modifier == 'alt') {
        if (alt) return null;
        alt = true;
      } else if (modifier == 'shift') {
        if (shift) return null;
        shift = true;
      } else {
        return null;
      }
    }
    return KeyChord(key: key, ctrl: ctrl, alt: alt, shift: shift);
  }

  static bool _isKnownKey(String key) =>
      _character.hasMatch(key) ||
      _namedKeys.contains(key) ||
      _functionKey.hasMatch(key);

  /// Canonical form: modifiers in ctrl+alt+shift order, then [key].
  String get label => [
        if (ctrl) 'ctrl',
        if (alt) 'alt',
        if (shift) 'shift',
        key,
      ].join('+');

  /// The JSON value of this chord: its [label].
  String toJson() => label;

  /// Reads a [label] string or a `{key, ctrl, alt, shift}` object.
  ///
  /// Throws [FormatException] when [json] holds no valid chord.
  factory KeyChord.fromJson(Object? json) {
    if (json is String) {
      final chord = tryParse(json);
      if (chord != null) return chord;
    } else if (json is Map) {
      final key = json['key'];
      if (key is String) {
        final label = [
          if (json['ctrl'] == true) 'ctrl',
          if (json['alt'] == true) 'alt',
          if (json['shift'] == true) 'shift',
          key,
        ].join('+');
        final chord = tryParse(label);
        if (chord != null) return chord;
      }
    }
    throw FormatException('Not a key chord', json);
  }

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift);

  @override
  String toString() => label;
}

/// One chord per player action, with the shipped bindings as defaults.
///
/// The stored form is a flat JSON object, one entry per action:
/// `{"upscaleOff":"ctrl+0",…,"screenshot":"s"}`.
class Keybindings {
  /// Starts from [defaults] and replaces the bindings named by [overrides].
  ///
  /// Throws [ArgumentError] when an override binds a chord that another
  /// action already holds, matching [assign].
  Keybindings({Map<PlayerAction, KeyChord>? overrides})
      : _bindings = Map.of(defaults) {
    if (overrides == null) return;
    for (final entry in overrides.entries) {
      _bind(entry.key, entry.value);
    }
  }

  /// The bindings the current app ships with.
  static const Map<PlayerAction, KeyChord> defaults = {
    PlayerAction.upscaleOff: KeyChord(key: '0', ctrl: true),
    PlayerAction.upscaleFast: KeyChord(key: '1', ctrl: true),
    PlayerAction.upscaleBalanced: KeyChord(key: '2', ctrl: true),
    PlayerAction.upscaleQuality: KeyChord(key: '3', ctrl: true),
    PlayerAction.toggleEnhance: KeyChord(key: 'e', ctrl: true),
    PlayerAction.subtitleDelayDown: KeyChord(key: 'z'),
    PlayerAction.subtitleDelayUp: KeyChord(key: 'x'),
    PlayerAction.speedDown: KeyChord(key: 'bracketleft'),
    PlayerAction.speedUp: KeyChord(key: 'bracketright'),
    PlayerAction.screenshot: KeyChord(key: 's'),
    PlayerAction.togglePlaylist: KeyChord(key: 'l'),
  };

  final Map<PlayerAction, KeyChord> _bindings;

  /// Read-only view of the current bindings; every action is always bound.
  Map<PlayerAction, KeyChord> get bindings => Map.unmodifiable(_bindings);

  KeyChord? chordFor(PlayerAction action) => _bindings[action];

  PlayerAction? actionFor(KeyChord chord) {
    for (final entry in _bindings.entries) {
      if (entry.value == chord) return entry.key;
    }
    return null;
  }

  /// Points [action] at [chord].
  ///
  /// Assigning the chord an action already holds is a no-op. Throws
  /// [ArgumentError] when another action holds [chord].
  void assign(PlayerAction action, KeyChord chord) {
    if (_bindings[action] == chord) return;
    _bind(action, chord);
  }

  void _bind(PlayerAction action, KeyChord chord) {
    final owner = actionFor(chord);
    if (owner != null && owner != action) {
      throw ArgumentError.value(
        chord.label,
        'chord',
        'already bound to ${owner.name}',
      );
    }
    _bindings[action] = chord;
  }

  /// Restores the built-in chord of [action].
  ///
  /// Another action that currently holds that chord is reset to its own
  /// default first, so the bindings never end up with duplicates.
  void reset(PlayerAction action) => _reset(action, <PlayerAction>{});

  void _reset(PlayerAction action, Set<PlayerAction> visiting) {
    // The guard only trips when actions hold each other's defaults; every
    // frame still writes its own default on the way out, so the result stays
    // free of duplicates.
    if (!visiting.add(action)) return;
    final fallback = defaults[action]!;
    if (_bindings[action] == fallback) return;
    final owner = actionFor(fallback);
    if (owner != null && owner != action) _reset(owner, visiting);
    _bindings[action] = fallback;
  }

  /// Restores every built-in chord.
  void resetAll() {
    _bindings
      ..clear()
      ..addAll(defaults);
  }

  /// The stored form: one entry per action.
  String toJson() => jsonEncode({
        for (final entry in _bindings.entries)
          entry.key.name: entry.value.toJson(),
      });

  /// Reads [raw], falling back to defaults for everything it cannot use.
  ///
  /// [overrides] replace the defaults before [raw] is applied, so a stored
  /// binding wins over an override. Unknown action names, unparsable chords,
  /// non-string values and chords another action already holds are skipped:
  /// a damaged settings file never throws, it just keeps what still parses.
  factory Keybindings.fromJson(
    String? raw, {
    Map<PlayerAction, KeyChord>? overrides,
  }) {
    final result = Keybindings();
    if (overrides != null) {
      for (final entry in overrides.entries) {
        result._bindIfFree(entry.key, entry.value);
      }
    }
    final decoded = _decode(raw);
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final action = _actionNamed(entry.key);
        if (action == null) continue;
        final chord = _chordFromJson(entry.value);
        if (chord == null) continue;
        result._bindIfFree(action, chord);
      }
    }
    return result;
  }

  void _bindIfFree(PlayerAction action, KeyChord chord) {
    final owner = actionFor(chord);
    if (owner != null && owner != action) return;
    _bindings[action] = chord;
  }

  static Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  static PlayerAction? _actionNamed(Object? name) {
    for (final action in PlayerAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }

  static KeyChord? _chordFromJson(Object? json) {
    try {
      return KeyChord.fromJson(json);
    } on FormatException {
      return null;
    }
  }
}

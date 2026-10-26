import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/settings/keybindings.dart';

/// Converts the Flutter-free [KeyChord] model to Flutter key types.
///
/// `lib/core` cannot import Flutter, so this mapping lives in the UI layer.
SingleActivator? activatorFor(KeyChord chord) {
  final key = _keyByChordName[chord.key];
  if (key == null) return null;
  return SingleActivator(
    key,
    control: chord.ctrl,
    alt: chord.alt,
    shift: chord.shift,
  );
}

/// Reads a key-down event into a [KeyChord]; modifier-only events return null.
///
/// Meta/Win is rejected because [KeyChord] has no meta modifier.
KeyChord? chordForEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isMetaPressed) return null;
  final name = _chordNameByKey[event.logicalKey];
  if (name == null) return null;
  return KeyChord(
    key: name,
    ctrl: keyboard.isControlPressed,
    alt: keyboard.isAltPressed,
    shift: keyboard.isShiftPressed,
  );
}

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const List<LogicalKeyboardKey> _letterKeys = [
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyC,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyE,
  LogicalKeyboardKey.keyF,
  LogicalKeyboardKey.keyG,
  LogicalKeyboardKey.keyH,
  LogicalKeyboardKey.keyI,
  LogicalKeyboardKey.keyJ,
  LogicalKeyboardKey.keyK,
  LogicalKeyboardKey.keyL,
  LogicalKeyboardKey.keyM,
  LogicalKeyboardKey.keyN,
  LogicalKeyboardKey.keyO,
  LogicalKeyboardKey.keyP,
  LogicalKeyboardKey.keyQ,
  LogicalKeyboardKey.keyR,
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyT,
  LogicalKeyboardKey.keyU,
  LogicalKeyboardKey.keyV,
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyX,
  LogicalKeyboardKey.keyY,
  LogicalKeyboardKey.keyZ,
];

const Map<String, LogicalKeyboardKey> _namedKeys = {
  'space': LogicalKeyboardKey.space,
  'enter': LogicalKeyboardKey.enter,
  'tab': LogicalKeyboardKey.tab,
  'escape': LogicalKeyboardKey.escape,
  'backspace': LogicalKeyboardKey.backspace,
  'delete': LogicalKeyboardKey.delete,
  'insert': LogicalKeyboardKey.insert,
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'pageup': LogicalKeyboardKey.pageUp,
  'pagedown': LogicalKeyboardKey.pageDown,
  'arrowup': LogicalKeyboardKey.arrowUp,
  'arrowdown': LogicalKeyboardKey.arrowDown,
  'arrowleft': LogicalKeyboardKey.arrowLeft,
  'arrowright': LogicalKeyboardKey.arrowRight,
  'bracketleft': LogicalKeyboardKey.bracketLeft,
  'bracketright': LogicalKeyboardKey.bracketRight,
  'backquote': LogicalKeyboardKey.backquote,
  'minus': LogicalKeyboardKey.minus,
  'equal': LogicalKeyboardKey.equal,
  'semicolon': LogicalKeyboardKey.semicolon,
  'quote': LogicalKeyboardKey.quote,
  'comma': LogicalKeyboardKey.comma,
  'period': LogicalKeyboardKey.period,
  'slash': LogicalKeyboardKey.slash,
  'backslash': LogicalKeyboardKey.backslash,
  'capslock': LogicalKeyboardKey.capsLock,
  'numlock': LogicalKeyboardKey.numLock,
  'scrolllock': LogicalKeyboardKey.scrollLock,
  'printscreen': LogicalKeyboardKey.printScreen,
  'pause': LogicalKeyboardKey.pause,
  'contextmenu': LogicalKeyboardKey.contextMenu,
  'mediaplaypause': LogicalKeyboardKey.mediaPlayPause,
  'mediastop': LogicalKeyboardKey.mediaStop,
  'medianexttrack': LogicalKeyboardKey.mediaTrackNext,
  'mediaprevioustrack': LogicalKeyboardKey.mediaTrackPrevious,
  'volumeup': LogicalKeyboardKey.audioVolumeUp,
  'volumedown': LogicalKeyboardKey.audioVolumeDown,
  'volumemute': LogicalKeyboardKey.audioVolumeMute,
};

const Map<String, LogicalKeyboardKey> _functionKeys = {
  'f1': LogicalKeyboardKey.f1,
  'f2': LogicalKeyboardKey.f2,
  'f3': LogicalKeyboardKey.f3,
  'f4': LogicalKeyboardKey.f4,
  'f5': LogicalKeyboardKey.f5,
  'f6': LogicalKeyboardKey.f6,
  'f7': LogicalKeyboardKey.f7,
  'f8': LogicalKeyboardKey.f8,
  'f9': LogicalKeyboardKey.f9,
  'f10': LogicalKeyboardKey.f10,
  'f11': LogicalKeyboardKey.f11,
  'f12': LogicalKeyboardKey.f12,
  'f13': LogicalKeyboardKey.f13,
  'f14': LogicalKeyboardKey.f14,
  'f15': LogicalKeyboardKey.f15,
  'f16': LogicalKeyboardKey.f16,
  'f17': LogicalKeyboardKey.f17,
  'f18': LogicalKeyboardKey.f18,
  'f19': LogicalKeyboardKey.f19,
  'f20': LogicalKeyboardKey.f20,
  'f21': LogicalKeyboardKey.f21,
  'f22': LogicalKeyboardKey.f22,
  'f23': LogicalKeyboardKey.f23,
  'f24': LogicalKeyboardKey.f24,
};

final Map<String, LogicalKeyboardKey> _keyByChordName = {
  for (var i = 0; i < _digitKeys.length; i++) '$i': _digitKeys[i],
  for (var i = 0; i < _letterKeys.length; i++)
    String.fromCharCode(0x61 + i): _letterKeys[i],
  ..._namedKeys,
  ..._functionKeys,
};

final Map<LogicalKeyboardKey, String> _chordNameByKey = {
  for (final entry in _keyByChordName.entries) entry.value: entry.key,
};

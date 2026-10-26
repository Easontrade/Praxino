import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/keybindings.dart';
import 'package:praxino/ui/key_chord_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps chord names to activators', () {
    final letter = activatorFor(const KeyChord(key: 'l'))!;
    expect(letter.trigger, LogicalKeyboardKey.keyL);
    expect(letter.control, isFalse);

    final digit = activatorFor(const KeyChord(key: '0', ctrl: true))!;
    expect(digit.trigger, LogicalKeyboardKey.digit0);
    expect(digit.control, isTrue);

    expect(activatorFor(const KeyChord(key: 'not-a-key')), isNull);
  });

  test('reads a key-down event', () {
    final event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyL,
      logicalKey: LogicalKeyboardKey.keyL,
      character: 'l',
      timeStamp: Duration.zero,
    );
    expect(chordForEvent(event), const KeyChord(key: 'l'));
  });

  test('ignores key-up events', () {
    final event = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyL,
      logicalKey: LogicalKeyboardKey.keyL,
      timeStamp: Duration.zero,
    );
    expect(chordForEvent(event), isNull);
  });
}

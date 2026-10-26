import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/settings/keybindings.dart';

/// Parses [raw] and fails the test when it is rejected.
KeyChord _chord(String raw) {
  final chord = KeyChord.tryParse(raw);
  expect(chord, isNotNull, reason: '"$raw" should parse');
  return chord!;
}

/// The default label of [action], for readable expectations.
String _defaultLabel(PlayerAction action) =>
    Keybindings.defaults[action]!.label;

void main() {
  group('KeyChord.tryParse', () {
    test('accepts plain keys and modifier combinations', () {
      expect(_chord('ctrl+1').label, 'ctrl+1');
      expect(_chord('shift+space').label, 'shift+space');
      expect(_chord('bracketleft').label, 'bracketleft');
      expect(_chord('alt+shift+z').label, 'alt+shift+z');
      expect(_chord('f12').label, 'f12');
      expect(_chord('arrowup').label, 'arrowup');
    });

    test('trims, lowercases and orders modifiers canonically', () {
      final chord = _chord(' SHIFT + Ctrl + 1 ');
      expect(chord.key, '1');
      expect(chord.ctrl, isTrue);
      expect(chord.shift, isTrue);
      expect(chord.alt, isFalse);
      expect(chord.label, 'ctrl+shift+1');
      expect(_chord('CTRL+E').label, 'ctrl+e');
    });

    test('rejects empty, unknown and malformed input', () {
      const garbage = [
        '',
        '   ',
        'ctrl+',
        '+1',
        'ctrl',
        'hyper+1',
        'control+1',
        'ctrl+ctrl+1',
        'ctrl+1+2',
        'ctrl++1',
        'nope',
        'f25',
        'media',
      ];
      for (final raw in garbage) {
        expect(KeyChord.tryParse(raw), isNull, reason: '"$raw" should be rejected');
      }
    });

    test('label round-trips through tryParse', () {
      const canonical = [
        'ctrl+0',
        'alt+f4',
        'shift+arrowup',
        'ctrl+alt+shift+1',
        'mediaplaypause',
        'bracketright',
      ];
      for (final raw in canonical) {
        final chord = _chord(raw);
        expect(chord.label, raw);
        expect(KeyChord.tryParse(chord.label), chord);
      }
    });

    test('has value equality', () {
      const ctrl1 = KeyChord(key: '1', ctrl: true);
      expect(ctrl1, _chord('ctrl+1'));
      expect(ctrl1.hashCode, _chord('ctrl+1').hashCode);
      expect(ctrl1, isNot(const KeyChord(key: '1')));
      expect(ctrl1, isNot(const KeyChord(key: '2', ctrl: true)));
      expect(const KeyChord(key: 'space', shift: true),
          _chord('shift+space'));
    });
  });

  group('KeyChord json', () {
    test('round-trips through its label', () {
      const chord = KeyChord(key: 'e', ctrl: true);
      expect(chord.toJson(), 'ctrl+e');
      expect(KeyChord.fromJson(chord.toJson()), chord);
      expect(KeyChord.fromJson('shift+space'),
          const KeyChord(key: 'space', shift: true));
    });

    test('reads an object form', () {
      expect(KeyChord.fromJson({'key': 'e', 'ctrl': true}),
          const KeyChord(key: 'e', ctrl: true));
      expect(KeyChord.fromJson({'key': '1'}), const KeyChord(key: '1'));
      expect(KeyChord.fromJson({'key': 'S', 'alt': true}).label, 'alt+s');
    });

    test('throws on garbage', () {
      for (final json in <Object?>[
        null,
        42,
        true,
        '',
        'hyper+1',
        <String, Object?>{'ctrl': true},
        <String, Object?>{'key': 7},
        <String, Object?>{},
      ]) {
        expect(() => KeyChord.fromJson(json), throwsFormatException,
            reason: '$json should be rejected');
      }
    });
  });

  group('Keybindings defaults', () {
    test('every action has a default', () {
      final keybindings = Keybindings();
      for (final action in PlayerAction.values) {
        expect(Keybindings.defaults[action], isNotNull, reason: action.name);
        expect(keybindings.chordFor(action), isNotNull, reason: action.name);
      }
      expect(keybindings.bindings.length, PlayerAction.values.length);
    });

    test('match the shortcuts the app ships with', () {
      final keybindings = Keybindings();
      const expected = {
        PlayerAction.upscaleOff: 'ctrl+0',
        PlayerAction.upscaleFast: 'ctrl+1',
        PlayerAction.upscaleBalanced: 'ctrl+2',
        PlayerAction.upscaleQuality: 'ctrl+3',
        PlayerAction.toggleEnhance: 'ctrl+e',
        PlayerAction.subtitleDelayDown: 'z',
        PlayerAction.subtitleDelayUp: 'x',
        PlayerAction.speedDown: 'bracketleft',
        PlayerAction.speedUp: 'bracketright',
        PlayerAction.screenshot: 's',
        PlayerAction.togglePlaylist: 'l',
      };
      expect(expected.length, PlayerAction.values.length);
      expected.forEach((action, label) {
        expect(keybindings.chordFor(action)!.label, label,
            reason: action.name);
      });
    });

    test('bindings are read-only', () {
      final keybindings = Keybindings();
      expect(
        () => keybindings.bindings[PlayerAction.screenshot] = _chord('f2'),
        throwsUnsupportedError,
      );
      expect(
        () => Keybindings.defaults[PlayerAction.screenshot] = _chord('f2'),
        throwsUnsupportedError,
      );
    });
  });

  group('assign', () {
    test('rejects a chord that another action already holds', () {
      final keybindings = Keybindings();
      final ctrl1 = keybindings.chordFor(PlayerAction.upscaleFast)!;

      expect(() => keybindings.assign(PlayerAction.screenshot, ctrl1),
          throwsArgumentError);
      expect(keybindings.chordFor(PlayerAction.screenshot)!.label, 's');
      expect(keybindings.actionFor(ctrl1), PlayerAction.upscaleFast);
    });

    test('allows the same action to keep the same chord', () {
      final keybindings = Keybindings();
      final ctrl1 = keybindings.chordFor(PlayerAction.upscaleFast)!;

      keybindings.assign(PlayerAction.upscaleFast, ctrl1);

      expect(keybindings.chordFor(PlayerAction.upscaleFast), ctrl1);
      expect(keybindings.actionFor(ctrl1), PlayerAction.upscaleFast);
    });

    test('binds a free chord and frees the previous one', () {
      final keybindings = Keybindings();
      final previous = keybindings.chordFor(PlayerAction.screenshot)!;

      keybindings.assign(PlayerAction.screenshot, _chord('f2'));

      expect(keybindings.chordFor(PlayerAction.screenshot)!.label, 'f2');
      expect(keybindings.actionFor(_chord('f2')), PlayerAction.screenshot);
      expect(keybindings.actionFor(previous), isNull);
    });
  });

  group('chordFor / actionFor', () {
    test('agree for every action', () {
      final keybindings = Keybindings();
      for (final action in PlayerAction.values) {
        expect(keybindings.actionFor(keybindings.chordFor(action)!), action,
            reason: action.name);
      }
    });

    test('an unbound chord maps to no action', () {
      final keybindings = Keybindings();
      expect(keybindings.actionFor(_chord('ctrl+q')), isNull);
      expect(keybindings.actionFor(const KeyChord(key: 's', ctrl: true)),
          isNull);
    });
  });

  group('reset', () {
    test('restores one action and leaves the others alone', () {
      final keybindings = Keybindings();
      keybindings.assign(PlayerAction.screenshot, _chord('f2'));
      keybindings.assign(PlayerAction.speedUp, _chord('f3'));

      keybindings.reset(PlayerAction.screenshot);

      expect(keybindings.chordFor(PlayerAction.screenshot)!.label, 's');
      expect(keybindings.chordFor(PlayerAction.speedUp)!.label, 'f3');
    });

    test('frees an action that took the restored default', () {
      final keybindings = Keybindings();
      keybindings.assign(PlayerAction.upscaleFast, _chord('space'));
      keybindings.assign(PlayerAction.upscaleOff, _chord('ctrl+1'));

      keybindings.reset(PlayerAction.upscaleFast);

      expect(keybindings.chordFor(PlayerAction.upscaleFast)!.label, 'ctrl+1');
      expect(keybindings.chordFor(PlayerAction.upscaleOff)!.label, 'ctrl+0');
      expect(keybindings.actionFor(_chord('ctrl+1')),
          PlayerAction.upscaleFast);
    });

    test('is a no-op for an action already on its default', () {
      final keybindings = Keybindings();
      keybindings.reset(PlayerAction.screenshot);
      expect(keybindings.chordFor(PlayerAction.screenshot)!.label, 's');
    });

    test('resetAll restores every default', () {
      final keybindings = Keybindings();
      keybindings.assign(PlayerAction.screenshot, _chord('f2'));
      keybindings.assign(PlayerAction.speedUp, _chord('f3'));
      keybindings.assign(PlayerAction.upscaleOff, _chord('f4'));

      keybindings.resetAll();

      for (final action in PlayerAction.values) {
        expect(keybindings.chordFor(action), Keybindings.defaults[action],
            reason: action.name);
      }
      expect(keybindings.bindings.length, PlayerAction.values.length);
    });
  });

  group('json', () {
    test('has one readable entry per action', () {
      final json = jsonDecode(Keybindings().toJson()) as Map<String, Object?>;

      expect(json.length, PlayerAction.values.length);
      expect(json['upscaleFast'], 'ctrl+1');
      expect(json['screenshot'], 's');
    });

    test('round-trips changed bindings', () {
      final keybindings = Keybindings()
        ..assign(PlayerAction.screenshot, _chord('alt+s'))
        ..assign(PlayerAction.speedDown, _chord('f10'));

      final restored = Keybindings.fromJson(keybindings.toJson());

      for (final action in PlayerAction.values) {
        expect(restored.chordFor(action), keybindings.chordFor(action),
            reason: action.name);
      }
    });

    test('skips unknown actions, bad chords and non-string values', () {
      final restored = Keybindings.fromJson(
        '{"nope":"ctrl+1","screenshot":"hyper+s","speedDown":17,'
        '"upscaleOff":["ctrl+0"],"upscaleQuality":"alt+3"}',
      );

      expect(restored.chordFor(PlayerAction.screenshot)!.label,
          _defaultLabel(PlayerAction.screenshot));
      expect(restored.chordFor(PlayerAction.speedDown)!.label,
          _defaultLabel(PlayerAction.speedDown));
      expect(restored.chordFor(PlayerAction.upscaleQuality)!.label, 'alt+3');
      expect(restored.bindings.length, PlayerAction.values.length);
    });

    test('skips a stored chord that another action already holds', () {
      final restored = Keybindings.fromJson('{"screenshot":"ctrl+1"}');

      expect(restored.chordFor(PlayerAction.screenshot)!.label, 's');
      expect(restored.chordFor(PlayerAction.upscaleFast)!.label, 'ctrl+1');
      expect(restored.actionFor(_chord('ctrl+1')), PlayerAction.upscaleFast);
    });

    test('accepts the chord object form', () {
      final restored = Keybindings.fromJson(
        '{"screenshot":{"key":"s","alt":true}}',
      );
      expect(restored.chordFor(PlayerAction.screenshot)!.label, 'alt+s');
    });

    test('falls back to defaults for missing or unusable storage', () {
      for (final raw in <String?>[
        null,
        '',
        'not json',
        '[]',
        '"ctrl+1"',
        '42',
        '{}',
      ]) {
        final restored = Keybindings.fromJson(raw);
        for (final action in PlayerAction.values) {
          expect(restored.chordFor(action), Keybindings.defaults[action],
              reason: '${raw ?? 'null'} / ${action.name}');
        }
      }
    });
  });

  group('overrides', () {
    test('replace defaults for the named actions only', () {
      final keybindings =
          Keybindings(overrides: {PlayerAction.screenshot: _chord('f2')});

      expect(keybindings.chordFor(PlayerAction.screenshot)!.label, 'f2');
      expect(keybindings.chordFor(PlayerAction.speedUp)!.label,
          'bracketright');
    });

    test('reject a chord that is already bound', () {
      expect(
        () => Keybindings(overrides: {
          PlayerAction.screenshot: _chord('ctrl+1'),
        }),
        throwsArgumentError,
      );
    });

    test('fromJson applies stored bindings over overrides', () {
      final restored = Keybindings.fromJson(
        '{"screenshot":"alt+s"}',
        overrides: {PlayerAction.screenshot: _chord('f2')},
      );

      expect(restored.chordFor(PlayerAction.screenshot)!.label, 'alt+s');
    });
  });
}

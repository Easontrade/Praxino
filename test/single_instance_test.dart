import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/platform/single_instance.dart';

void main() {
  test('parses newline-separated arguments', () {
    expect(
      SingleInstance.parsePayload('D:\\a b\\c.mkv\nhttps://example.test/x\n'),
      ['D:\\a b\\c.mkv', 'https://example.test/x'],
    );
    expect(SingleInstance.parsePayload(''), isEmpty);
  });
}

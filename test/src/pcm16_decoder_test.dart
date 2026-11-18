import 'dart:typed_data';

import 'package:farsi_speech_to_text/src/pcm16_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pcm16Decoder', () {
    test('decodes signed little-endian samples into normalized floats', () {
      final decoder = Pcm16Decoder();
      final input = Uint8List.fromList([0, 128, 255, 127, 0, 0, 0, 64]);

      expect(decoder.add(input), [-1.0, 32767 / 32768, 0.0, 0.5]);
      decoder.finish();
    });

    test('keeps an incomplete sample across chunks and empty chunks', () {
      final decoder = Pcm16Decoder();

      expect(decoder.add(Uint8List.fromList([0])), isEmpty);
      expect(decoder.add(Uint8List(0)), isEmpty);
      expect(decoder.add(Uint8List.fromList([128, 0, 64, 0])), [-1.0, 0.5]);
      expect(decoder.add(Uint8List.fromList([0])), [0.0]);
      decoder.finish();
    });

    test('rejects a trailing byte when the recording ends', () {
      final decoder = Pcm16Decoder()..add(Uint8List.fromList([1]));
      expect(decoder.finish, throwsFormatException);
    });
  });
}

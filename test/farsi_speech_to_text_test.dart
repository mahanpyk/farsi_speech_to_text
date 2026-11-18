import 'dart:io';
import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FarsiModel model;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('farsi_asr_test_');
    model = FarsiModel.at(directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test('reports an empty model directory as missing', () async {
    expect(await model.isInstalled(), isFalse);
  });

  test('reports a truncated model directory as missing', () async {
    for (final name in [
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
      'LICENSE',
      'NOTICE',
    ]) {
      await File('${directory.path}/$name').writeAsString('incomplete');
    }
    expect(await model.isInstalled(), isFalse);
  });

  test('rejects non-positive thread counts', () {
    expect(
      () => FarsiSpeechToText(model: model, numThreads: 0),
      throwsArgumentError,
    );
  });

  test('reports a missing WAV before starting inference', () async {
    final recognizer = FarsiSpeechToText(model: model);
    await expectLater(
      recognizer.transcribeWav('${directory.path}/missing.wav'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'reports a missing model before opening the live audio source',
    () async {
      var listened = false;
      Stream<Uint8List> audio() async* {
        listened = true;
        yield Uint8List(2);
      }

      final recognizer = FarsiSpeechToText(model: model);
      await expectLater(
        recognizer.transcribePcm16(audio()),
        emitsError(isA<FileSystemException>()),
      );
      expect(listened, isFalse);
    },
  );
}

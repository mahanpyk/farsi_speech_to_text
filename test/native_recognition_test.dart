import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final modelPath = Platform.environment['FARSI_TEST_MODEL'];
  final wavPath = Platform.environment['FARSI_TEST_WAV'];

  group(
    'Native Persian inference',
    () {
      late FarsiSpeechToText recognizer;
      late Uint8List pcm;
      late String wavTranscript;

      setUpAll(() async {
        recognizer = FarsiSpeechToText(
          model: FarsiModel.at(Directory(modelPath!)),
        );
        final wav = await File(wavPath!).readAsBytes();
        final data = ByteData.sublistView(wav);
        // The upstream demo fixture has a canonical PCM WAV header.
        expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
        expect(data.getUint16(22, Endian.little), 1);
        expect(data.getUint32(24, Endian.little), 16000);
        expect(data.getUint16(34, Endian.little), 16);
        pcm = Uint8List.sublistView(wav, 44);
        wavTranscript = await recognizer.transcribeWav(wavPath);
      });

      test(
        'transcribes a Persian WAV and produces matching streaming text',
        () async {
          expect(
            wavTranscript,
            matches(RegExp(r'[آابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی]+')),
          );
          final events = await recognizer
              .transcribePcm16(_chunks(pcm))
              .toList();
          expect(events.length, greaterThan(1));
          expect(
            events.take(events.length - 1).every((event) => !event.isFinal),
            isTrue,
          );
          expect(events.last.isFinal, isTrue);
          expect(events.last.text, wavTranscript);
        },
      );

      test('cancels an open PCM source before it emits a transcript', () async {
        final listening = Completer<void>();
        final canceled = Completer<void>();
        final source = StreamController<Uint8List>(
          onListen: listening.complete,
          onCancel: canceled.complete,
        );
        addTearDown(source.close);

        final speech = recognizer
            .transcribePcm16(source.stream)
            .listen((_) => fail('No audio was supplied.'));
        await listening.future;
        await speech.cancel().timeout(const Duration(seconds: 5));
        await canceled.future.timeout(const Duration(seconds: 5));
      });

      test('reports a PCM stream ending mid-sample', () async {
        await expectLater(
          recognizer.transcribePcm16(Stream.value(Uint8List(1))),
          emitsError(isA<FormatException>()),
        );
      });
    },
    skip: modelPath == null || wavPath == null
        ? 'Requires the pinned model, native Sherpa library and demo WAV.'
        : false,
  );
}

Stream<Uint8List> _chunks(Uint8List pcm) async* {
  const chunkSize = 3189;
  for (var offset = 0; offset < pcm.length; offset += chunkSize) {
    final end = (offset + chunkSize).clamp(0, pcm.length);
    yield Uint8List.sublistView(pcm, offset, end);
  }
}

import 'dart:typed_data';

import '../farsi_transcript.dart';

final class WebRuntime {
  WebRuntime(Uri? _) {
    throw _unsupported();
  }

  Future<void> prepare(void Function(double)? onProgress) =>
      throw _unsupported();
  Future<String> transcribeWavBytes(Uint8List wav) => throw _unsupported();
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) =>
      throw _unsupported();
  void dispose() => throw _unsupported();
}

UnsupportedError _unsupported() =>
    UnsupportedError('FarsiWebSpeechToText requires a browser.');

import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:file_selector/file_selector.dart';

import 'demo_backend.dart';

Future<DemoBackend> createBackend() async {
  const modelUrl = String.fromEnvironment('FARSI_MODEL_BASE_URL');
  return _BrowserBackend(
    FarsiWebSpeechToText(
      modelBaseUri: modelUrl.isEmpty ? null : Uri.base.resolve(modelUrl),
    ),
  );
}

bool needsModelPreparation(Object error) => false;

final class _BrowserBackend implements DemoBackend {
  _BrowserBackend(this._recognizer);

  final FarsiWebSpeechToText _recognizer;

  @override
  Future<bool> isPrepared() async => false;

  @override
  Future<void> prepare({required void Function(double) onProgress}) =>
      _recognizer.prepare(onProgress: onProgress);

  @override
  Future<String> transcribeFile(XFile file) async =>
      _recognizer.transcribeWavBytes(await file.readAsBytes());

  @override
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) =>
      _recognizer.transcribePcm16(audio);

  @override
  void dispose() => _recognizer.dispose();
}

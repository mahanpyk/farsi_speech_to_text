import 'dart:io';
import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'demo_backend.dart';

Future<DemoBackend> createBackend() async {
  final support = await getApplicationSupportDirectory();
  final model = FarsiModel.at(
    Directory(p.join(support.path, 'nemotron-farsi-int8')),
  );
  return _NativeBackend(FarsiSpeechToText(model: model));
}

bool needsModelPreparation(Object error) => error is FarsiModelException;

final class _NativeBackend implements DemoBackend {
  _NativeBackend(this._recognizer);

  final FarsiSpeechToText _recognizer;

  @override
  Future<bool> isPrepared() => _recognizer.model.isInstalled();

  @override
  Future<void> prepare({required void Function(double) onProgress}) =>
      _recognizer.model.download(onProgress: onProgress);

  @override
  Future<String> transcribeFile(XFile file) =>
      _recognizer.transcribeWav(file.path);

  @override
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) =>
      _recognizer.transcribePcm16(audio);

  @override
  void dispose() {}
}

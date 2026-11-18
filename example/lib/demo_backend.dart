import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:file_selector/file_selector.dart';

abstract interface class DemoBackend {
  Future<bool> isPrepared();
  Future<void> prepare({required void Function(double) onProgress});
  Future<String> transcribeFile(XFile file);
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio);
  void dispose();
}

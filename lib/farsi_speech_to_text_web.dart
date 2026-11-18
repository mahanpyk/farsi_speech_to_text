/// Browser speech recognition with the Persian Nemotron model.
library;

import 'dart:typed_data';

import 'src/farsi_transcript.dart';
import 'src/web/runtime_stub.dart'
    if (dart.library.js_interop) 'src/web/runtime.dart';

export 'src/farsi_transcript.dart';

/// Recognizes Persian speech in a dedicated browser worker.
final class FarsiWebSpeechToText {
  /// Creates a browser recognizer with an optional model mirror.
  ///
  /// [modelBaseUri] points to a directory serving the exact pinned model files.
  /// When omitted, the package uses its pinned Hugging Face model revision.
  /// Throws an [UnsupportedError] outside the browser.
  FarsiWebSpeechToText({Uri? modelBaseUri})
    : _runtime = WebRuntime(_modelDirectory(modelBaseUri));

  final WebRuntime _runtime;

  /// Downloads, verifies, and loads the model in the browser.
  ///
  /// The first download uses about 666 MB of origin-private file storage.
  /// [onProgress] receives the fraction of model bytes available from zero to
  /// one. A HTTPS or localhost page with WebAssembly and worker support is
  /// required. Concurrent calls share the first callback.
  Future<void> prepare({void Function(double fraction)? onProgress}) =>
      _runtime.prepare(onProgress);

  /// Transcribes a non-empty mono, 16-bit PCM WAV from bytes.
  ///
  /// Prepares the model on first use. Throws [FormatException] for unsupported
  /// or malformed WAV data and [StateError] if a transcription is in progress.
  Future<String> transcribeWavBytes(Uint8List wav) =>
      _runtime.transcribeWavBytes(wav);

  /// Transcribes 16 kHz mono, signed little-endian PCM16 audio.
  ///
  /// Each update contains cumulative text. Closing [audio] produces one final
  /// update. Cancel the returned subscription to end the current session.
  /// Prepares the model before listening to audio on first use.
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) =>
      _runtime.transcribePcm16(audio);

  /// Terminates the worker and releases its memory.
  ///
  /// The browser keeps the verified model in its origin-private storage.
  void dispose() => _runtime.dispose();
}

Uri? _modelDirectory(Uri? uri) {
  if (uri == null) return null;
  if ((uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(
      uri,
      'modelBaseUri',
      'Expected an HTTP directory URL.',
    );
  }
  return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
}

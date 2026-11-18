/// Offline Persian speech recognition for Flutter.
library;

export 'farsi_speech_to_text_web.dart' show FarsiWebSpeechToText;
export 'src/farsi_transcript.dart' show FarsiTranscript;
export 'src/native_exports.dart'
    if (dart.library.js_interop) 'src/native_unavailable.dart';

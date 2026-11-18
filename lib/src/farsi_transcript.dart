/// A cumulative Persian transcript from one recognition session.
final class FarsiTranscript {
  /// Creates a partial or final transcript for an audio stream.
  const FarsiTranscript({required this.text, required this.isFinal});

  /// The recognized text so far, which may change in later updates.
  final String text;

  /// Whether the audio ended and the recognizer flushed its remaining text.
  final bool isFinal;
}

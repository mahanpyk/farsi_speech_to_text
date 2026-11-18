# Persian speech-to-text demo

The Flutter demo shows live microphone transcription and WAV file transcription with a Persian, right-to-left interface.

## Run the app

Use Flutter 3.50 and Dart 3.14 for the demo. From the package directory, run the following on macOS.

```sh
cd example
flutter pub get
flutter run -d macos
```

For Android or iOS, run `flutter devices`, then `flutter run -d <device-id>`. An iOS device build uses your local signing settings.

Run `flutter run -d linux` on Linux or `flutter run -d windows` on Windows. Linux microphone capture uses `parecord`, `pactl`, and `ffmpeg`. [Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup) · [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup) · [Linux recorder prerequisites](https://pub.dev/packages/record/versions/6.2.0#linux)

Run `flutter run -d chrome` for the browser demo. For a hosted deployment, serve the build over HTTPS. If you host an exact copy of the model files on a mirror, set `FARSI_MODEL_BASE_URL` to its directory.

```sh
flutter run -d chrome --dart-define=FARSI_MODEL_BASE_URL=https://example.com/models/
```

## Try transcription

1. Select **آماده‌سازی مدل** to prepare the model. The initial download is 666.6 MB. The native app stores it in its support directory, and the browser stores it for the current site.
2. Select **شروع ضبط** and allow microphone access. The app shows Persian text as it recognizes the recording. Select **توقف ضبط** to finish.
3. Select **انتخاب فایل WAV** to transcribe a non-empty, mono, 16-bit PCM WAV file.
4. Select **کپی متن** to copy the result.

See the [package README](../README.md) for the Dart API, supported platforms, permissions, and attribution.

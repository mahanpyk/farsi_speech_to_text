# Contributing

Describe the problem and expected behavior in the pull request. Link an existing issue when one applies. For a change you can reproduce, include enough detail for someone else to see the original behavior and verify the result.

## Open a pull request

If you use a fork, branch from the upstream default branch, push the change to your fork, and open the pull request against the upstream default branch. Use a draft while the evidence is still incomplete. The [pull request template](.github/pull_request_template.md) asks for the behavior change, actual validation, and any documentation or compatibility impact.

Update public API doc comments, the English README, the changelog, or the example when the change affects what callers need to know. For an API or platform change, describe the impact on existing callers and how they can adapt.

## Verify the change

Use the package's supported Flutter and Dart versions from its [pubspec](pubspec.yaml). From the package root, install the library and example dependencies.

```sh
flutter pub get
(cd example && flutter pub get)
```

Run the checks that apply to your change.

| Area | Local check |
| --- | --- |
| Changed Dart files | `dart format --output=none --set-exit-if-changed path/to/changed.dart` |
| Package analysis and VM tests | `flutter analyze lib test` and `flutter test` |
| Browser adapter tests | `flutter test --platform chrome test/web` |
| Flutter example | `cd example`, then `flutter analyze` and `flutter test` |
| Example release build | Run `flutter build` for the affected target from `example/`. For Web changes, check both `flutter build web` and `flutter build web --wasm` when relevant. |

For changes to native WAV or PCM recognition, the opt-in `test/native_recognition_test.dart` suite uses the exact pinned model and real Persian speech. Set `FARSI_TEST_MODEL` to the directory that contains the pinned files and `FARSI_TEST_WAV` to a canonical mono, 16 kHz PCM16 WAV fixture. Make the target Sherpa native library available to the test process, then run `flutter test test/native_recognition_test.dart`. You can also reproduce an affected device path in the [example app](example/).

For browser inference changes, use the example in Chrome with the pinned model and a real WAV or PCM source. Exercise relevant paths such as downloading or reusing the cache, receiving a final transcript, and canceling a stream. The browser unit tests can run without the model weights. The full pinned model requires a separate download of about 666.6 MB.

For model changes, report the pinned revision and digests of changed files. For runtime changes, give the exact dependency version. Include the sample and platform used to verify recognition. If distribution size changes, compare release builds with the same target architecture, SDK, and settings. Report the package archive, compiled app, and downloaded model sizes separately. [Model provenance and size methodology](README.md#model-privacy-and-app-size)

In the pull request, record the commands and observed results. Give a reason for any check marked `N/A`. For an applicable check you could not run, state what remains unverified. Report local results, this pull request's GitHub Actions result, and any `main` GitHub Actions result separately. Fork runs may be pending maintainer approval.

The `CI` workflow checks formatting on changed Dart files, analysis, tests, and example builds. Its aggregate check is named `Required checks`. The regular CI jobs use lightweight tests. Provide separate evidence for any real-model or device behavior your change relies on.

## AI-assisted contributions

You are responsible for the full diff and the accuracy of the pull request description. Read and understand any AI-assisted edits before submitting. Personally verify the technical claims and inspect the actual output of the checks you report. In the author review section, say where AI helped and how you verified those parts.

Treat automated reviewer comments as advisory feedback. Check them against the diff and test evidence, and bring uncertain findings to the human reviewer.

Maintainers can find merge settings and automation setup in the [maintainer guide](doc/maintainer-pr-workflow.md).

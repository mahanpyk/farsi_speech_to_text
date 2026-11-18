# Review guidelines

Use these criteria to review changes to Persian speech recognition, platform integration, and release and CI claims. Cite the affected code and evidence when raising a finding.

## Runtime boundaries

- Keep native file I/O and Sherpa FFI in the native Dart implementation. Keep browser interop and on-device WebAssembly inference in the Web adapter and its dedicated worker. Check that conditional imports preserve both native and Web builds.
- Process audio locally. Model downloads may contact the pinned host or a configured mirror. Audio and transcripts should stay on the device.

## Model downloads and storage

- Keep the ONNX graphs, tokenizer, license, and notice pinned to the same upstream revision on native and Web. Check exact byte lengths and SHA-256 digests before loading. If the revision changes, update the pinned metadata and cache identity together.
- Keep model weights outside source control and shipped package or example assets. Check that failed downloads and corrupt cache entries can be retried and that verified files can be reused offline.

## Audio and recording

- Preserve the PCM contract of 16 kHz mono, signed little-endian 16-bit samples. Review partial sample boundaries, streaming backpressure, the final transcript, and errors on malformed audio.
- Check microphone permission handling and recorder cleanup on stop, cancel, errors, and disposal. Check the worker or native session releases its resources and that a canceled session cannot affect a later recording.

## Validation and merge checks

- Match claims to observed evidence. A successful build supports a build claim. A runtime, recognition, privacy, size, or platform claim should cite the relevant test, fixture, target, or measurement.
- Keep pull request CI compatible with a read-only token and public dependencies. Flag privileged execution of code contributed from forks, expanded token scopes, credential persistence, and unpinned third-party actions. Preserve the unique `Required checks` job and its aggregation of the mandatory CI jobs. Automated review provides feedback for human reviewers.

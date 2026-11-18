@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

@JS('Worker')
external JSFunction get _workerConstructor;

@JS('Worker')
external set _workerConstructor(JSFunction constructor);

void main() {
  test('requires an HTTP model base with directory URL semantics', () {
    for (final invalid in [
      'file:///models/',
      'models/',
      'https://example.com/models/?token=1',
      'https://example.com/models/#section',
    ]) {
      expect(
        () => FarsiWebSpeechToText(modelBaseUri: Uri.parse(invalid)),
        throwsArgumentError,
        reason: invalid,
      );
    }
  });

  test('rejects prepare and audio after disposal', () async {
    final speech = FarsiWebSpeechToText();
    speech.dispose();
    speech.dispose();

    await expectLater(speech.prepare(), throwsStateError);
    await expectLater(
      speech.transcribeWavBytes(Uint8List(0)),
      throwsStateError,
    );
    await expectLater(
      speech.transcribePcm16(const Stream<Uint8List>.empty()),
      emitsError(isA<StateError>()),
    );
  });

  test('cancels PCM immediately while model preparation is pending', () async {
    final original = _workerConstructor;
    final shim = web.document.createElement('script') as web.HTMLScriptElement;
    shim.text = '''
      {
        const NativeWorker = globalThis.Worker;
        const source = `
          self.onmessage = ({data}) => {
            if (data.type === 'prepare') {
              self.postMessage({id:data.id, progress:0.25});
            }
          };
        `;
        globalThis.Worker = class extends NativeWorker {
          constructor() {
            const url = URL.createObjectURL(new Blob([source], {type:'text/javascript'}));
            super(url);
            URL.revokeObjectURL(url);
          }
        };
      }
    ''';
    web.document.head!.appendChild(shim);
    shim.remove();
    addTearDown(() => _workerConstructor = original);

    final speech = FarsiWebSpeechToText();
    addTearDown(speech.dispose);
    final preparing = Completer<void>();
    final ready = speech.prepare(onProgress: (_) => preparing.complete());
    final readyEndsOnDispose = expectLater(ready, throwsStateError);
    await preparing.future;

    final sub = speech
        .transcribePcm16(const Stream<Uint8List>.empty())
        .listen(null);
    await sub.cancel().timeout(const Duration(seconds: 2));

    final next = speech.transcribeWavBytes(Uint8List(0));
    final nextEndsOnDispose = expectLater(
      next,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('disposed'),
        ),
      ),
    );
    speech.dispose();
    await readyEndsOnDispose;
    await nextEndsOnDispose;
  });
}

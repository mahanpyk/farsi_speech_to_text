import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../farsi_transcript.dart';

final class WebRuntime {
  WebRuntime(this._modelBaseUri);

  final Uri? _modelBaseUri;
  _WorkerClient? _client;
  Future<void>? _ready;
  StreamIterator<Uint8List>? _activeInput;
  Object? _activeSession;
  bool _disposed = false;

  Future<void> prepare(void Function(double)? onProgress) async {
    _checkOpen();
    if (_client?.closed ?? false) {
      _client = null;
      _ready = null;
    }
    if (_ready case final pending?) {
      await pending;
      return;
    }
    if (!web.window.isSecureContext) {
      throw StateError(
        'Persian speech recognition requires HTTPS or localhost.',
      );
    }

    final worker = _client ??= _WorkerClient(_cancelInput);
    final task = worker
        .request(
          'prepare',
          modelBase: _modelBaseUri?.toString(),
          onProgress: onProgress,
        )
        .then<void>((_) {});
    _ready = task;
    try {
      await task;
    } catch (_) {
      _ready = null;
      if (worker.closed) _client = null;
      rethrow;
    }
  }

  Future<String> transcribeWavBytes(Uint8List wav) async {
    final session = Object();
    _begin(session);
    try {
      await prepare(null);
      final result = await _client!.request('wav', bytes: wav);
      return result ?? '';
    } finally {
      _end(session);
    }
  }

  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) {
    late final StreamController<FarsiTranscript> results;
    final completed = Completer<void>();
    final session = Object();
    StreamIterator<Uint8List>? input;
    var canceled = false;
    var openingStream = false;

    Future<void> recognize() async {
      var started = false;
      try {
        _begin(session);
        await prepare(null);
        if (canceled) return;
        final worker = _client!;
        openingStream = true;
        await worker.request('begin');
        started = true;
        if (canceled) return;

        final source = input = _activeInput = StreamIterator(audio);
        var previous = '';
        while (!canceled && !_disposed && await source.moveNext()) {
          final bytes = source.current;
          if (bytes.isEmpty) continue;
          final text = await worker.request('pcm', bytes: bytes) ?? '';
          if (!canceled && text != previous) {
            previous = text;
            results.add(FarsiTranscript(text: text, isFinal: false));
          }
        }
        if (canceled) return;
        _checkOpen();
        final text = await worker.request('finish') ?? '';
        started = false;
        if (!canceled) results.add(FarsiTranscript(text: text, isFinal: true));
      } catch (error, stack) {
        if (!canceled) results.addError(error, stack);
      } finally {
        if (started && !_disposed) {
          try {
            await _client?.request('end');
          } catch (_) {
            // The worker closed or has already released the stream.
          }
        }
        try {
          await input?.cancel();
        } finally {
          _end(session);
          completed.complete();
          unawaited(results.close());
        }
      }
    }

    results = StreamController(
      onListen: () => unawaited(recognize()),
      onCancel: () async {
        canceled = true;
        if (!openingStream) {
          // A canceled caller can leave the shared model preparation running.
          _end(session);
          return;
        }
        await input?.cancel();
        await completed.future;
      },
    );
    return results.stream;
  }

  void _checkOpen() {
    if (_disposed) {
      throw StateError('The Persian speech recognizer is disposed.');
    }
  }

  void _begin(Object session) {
    _checkOpen();
    if (_activeSession != null) {
      throw StateError('A Persian transcription is already running.');
    }
    _activeSession = session;
  }

  void _end(Object session) {
    if (identical(_activeSession, session)) {
      _activeSession = null;
      _activeInput = null;
    }
  }

  void _cancelInput() {
    final input = _activeInput;
    if (input != null) unawaited(input.cancel().catchError((Object _) {}));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client?.close(StateError('The Persian speech recognizer is disposed.'));
    _cancelInput();
  }
}

extension type _Command._(JSObject _) implements JSObject {
  external factory _Command({
    required int id,
    required String type,
    String? modelBase,
    JSUint8Array? bytes,
  });
}

extension type _TransferBytes(JSUint8Array _) implements JSUint8Array {
  external JSArrayBuffer get buffer;
}

extension type _WorkerError(JSObject _) implements JSObject {
  external String? get message;
}

extension type _Reply._(JSObject _) implements JSObject {
  external int get id;
  external String? get text;
  external String? get error;
  external bool? get formatError;
  external double? get progress;
}

typedef _Request = ({
  Completer<String?> result,
  void Function(double)? onProgress,
});

final class _WorkerClient {
  _WorkerClient(this._onClose)
    : _worker = web.Worker(
        Uri.parse(web.document.baseURI)
            .resolve(
              'assets/packages/farsi_speech_to_text/assets/farsi_worker.js',
            )
            .toString()
            .toJS,
      ) {
    _worker.onmessage = _handleReply.toJS;
    _worker.onerror = ((web.Event event) {
      final detail =
          _WorkerError(event).message ?? 'Could not load its script.';
      close(StateError('Persian speech worker failed: $detail'));
    }).toJS;
    _worker.onmessageerror = ((web.Event _) {
      close(StateError('The Persian speech worker sent an invalid response.'));
    }).toJS;
  }

  final web.Worker _worker;
  final void Function() _onClose;
  final _pending = <int, _Request>{};
  var _lastId = 0;
  Object? _failure;

  bool get closed => _failure != null;

  Future<String?> request(
    String type, {
    String? modelBase,
    Uint8List? bytes,
    void Function(double)? onProgress,
  }) async {
    if (_failure case final error?) throw error;

    final id = _lastId++;
    final result = Completer<String?>();
    _pending[id] = (result: result, onProgress: onProgress);
    // Transfer a private copy so callers can still use their original bytes.
    final transferBytes = bytes == null ? null : Uint8List.fromList(bytes).toJS;
    final request = _Command(
      id: id,
      type: type,
      modelBase: modelBase,
      bytes: transferBytes,
    );

    try {
      if (transferBytes == null) {
        _worker.postMessage(request);
      } else {
        _worker.postMessage(
          request,
          [_TransferBytes(transferBytes).buffer].toJS,
        );
      }
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }
    return result.future;
  }

  void _handleReply(web.MessageEvent event) {
    final reply = event.data as _Reply;
    final request = _pending[reply.id];
    if (request == null) return;
    if (reply.progress case final progress?) {
      request.onProgress?.call(progress);
      return;
    }

    _pending.remove(reply.id);
    if (reply.error case final error?) {
      request.result.completeError(
        (reply.formatError ?? false)
            ? FormatException(error)
            : StateError(error),
      );
    } else {
      request.result.complete(reply.text);
    }
  }

  void close(Object error) {
    if (closed) return;
    _failure = error;
    _worker.terminate();
    _worker.onmessage = null;
    _worker.onerror = null;
    _worker.onmessageerror = null;

    for (final request in _pending.values) {
      request.result.completeError(error);
    }
    _pending.clear();
    _onClose();
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'farsi_model.dart';
import 'farsi_transcript.dart';
import 'pcm16_decoder.dart';

const _sampleRate = 16000;

/// Recognizes Persian speech locally with the fine-tuned Nemotron model.
final class FarsiSpeechToText {
  /// Creates a recognizer backed by [model] and [numThreads] CPU threads.
  FarsiSpeechToText({required this.model, this.numThreads = 2}) {
    RangeError.checkValueInInterval(numThreads, 1, 32, 'numThreads');
  }

  /// The installed Persian model.
  final FarsiModel model;

  /// The number of inference threads, between 1 and 32.
  final int numThreads;

  /// Transcribes a non-empty mono, 16-bit PCM WAV file.
  ///
  /// Loads the WAV into memory and runs inference in a background isolate.
  /// Throws a [FormatException] if the WAV cannot be decoded.
  Future<String> transcribeWav(String path) async {
    if (!await File(path).exists()) {
      throw FileSystemException('Audio file not found', path);
    }
    await model.verify();
    final directory = model.directory.path;
    final threads = numThreads;
    return Isolate.run(() => _decodeWav(path, directory, threads));
  }

  /// Transcribes a stream of 16 kHz mono, signed little-endian PCM16 audio.
  ///
  /// Each event contains the full transcript so far. Closing [audio] flushes
  /// the buffered samples and produces one final update, even for empty input.
  /// Cancel the returned subscription to release recognition resources early.
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) {
    late final StreamController<FarsiTranscript> results;
    StreamIterator<Uint8List>? input;
    var canceled = false;

    Future<void> recognize() async {
      final replyPort = ReceivePort();
      final replies = StreamIterator<Object?>(replyPort);
      SendPort? commands;
      try {
        await model.verify();
        if (canceled) return;
        await Isolate.spawn(
          _decodeStream,
          (replyPort.sendPort, model.directory.path, numThreads),
          onError: replyPort.sendPort,
          onExit: replyPort.sendPort,
        );
        final commandPort = await _readReply(replies) as SendPort;
        commands = commandPort;
        if (canceled) return;
        final source = input = StreamIterator(audio);
        var previous = '';
        while (!canceled && await source.moveNext()) {
          final bytes = source.current;
          if (bytes.isEmpty) continue;
          commandPort.send(TransferableTypedData.fromList([bytes]));
          final text = await _readReply(replies) as String;
          if (!canceled && text != previous) {
            previous = text;
            results.add(FarsiTranscript(text: text, isFinal: false));
          }
        }
        if (canceled) return;
        commandPort.send(true);
        final text = await _readReply(replies) as String;
        if (!canceled) results.add(FarsiTranscript(text: text, isFinal: true));
      } catch (error, stack) {
        if (!canceled) results.addError(error, stack);
      } finally {
        commands?.send(null);
        await input?.cancel();
        await replies.cancel();
        replyPort.close();
        unawaited(results.close());
      }
    }

    results = StreamController(
      onListen: () => unawaited(recognize()),
      onCancel: () async {
        canceled = true;
        await input?.cancel();
      },
    );
    return results.stream;
  }
}

Future<Object> _readReply(StreamIterator<Object?> replies) async {
  if (await replies.moveNext()) {
    final message = replies.current;
    if (message is List<Object?> && message.length == 2) {
      throw RemoteError(message[0].toString(), message[1].toString());
    }
    if (message is FormatException) throw message;
    if (message != null) return message;
  }
  throw StateError('The Persian speech recognizer exited unexpectedly.');
}

Future<void> _decodeStream((SendPort, String, int) options) async {
  final (replies, directory, threads) = options;
  final engine = _Engine.open(directory, threads);
  final commands = ReceivePort();
  final decoder = Pcm16Decoder();
  var hasAudio = false;
  var previous = '';

  try {
    replies.send(commands.sendPort);
    await for (final input in commands) {
      if (input == null) break;
      if (input == true) {
        final String text;
        try {
          decoder.finish();
          text = hasAudio ? engine.finish(_sampleRate) : '';
        } on FormatException catch (error) {
          replies.send(error);
          break;
        }
        replies.send(text);
        break;
      }

      final bytes = (input as TransferableTypedData)
          .materialize()
          .asUint8List();
      final samples = decoder.add(bytes);
      if (samples.isNotEmpty) {
        hasAudio = true;
        if (engine.add(samples, _sampleRate)) previous = engine.text;
      }
      replies.send(previous);
    }
  } finally {
    commands.close();
    engine.close();
  }
}

String _decodeWav(String path, String directory, int threads) {
  sherpa.initBindings();
  final wave = sherpa.readWave(path);
  if (wave.samples.isEmpty || wave.sampleRate <= 0) {
    throw FormatException('Expected a non-empty mono, 16-bit PCM WAV.', path);
  }

  final engine = _Engine.open(directory, threads, inputRate: wave.sampleRate);
  try {
    for (
      var offset = 0;
      offset < wave.samples.length;
      offset += wave.sampleRate
    ) {
      final end = math.min(offset + wave.sampleRate, wave.samples.length);
      engine.add(
        Float32List.sublistView(wave.samples, offset, end),
        wave.sampleRate,
      );
    }
    return engine.finish(wave.sampleRate);
  } finally {
    engine.close();
  }
}

final class _Engine {
  _Engine(this._recognizer, this._stream);

  factory _Engine.open(
    String directory,
    int threads, {
    int inputRate = _sampleRate,
  }) {
    sherpa.initBindings();
    final recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: _sampleRate,
          featureDim: 128,
        ),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: p.join(directory, encoderName),
            decoder: p.join(directory, decoderName),
            joiner: p.join(directory, joinerName),
          ),
          tokens: p.join(directory, tokensName),
          numThreads: threads,
          debug: false,
        ),
        enableEndpoint: false,
      ),
    );

    sherpa.OnlineStream? stream;
    try {
      stream = recognizer.createStream();
      stream.setOption(key: 'language', value: 'fa-IR');
      // The exported streaming model can miss the first word without priming.
      stream.acceptWaveform(
        samples: Float32List(inputRate ~/ 2),
        sampleRate: inputRate,
      );
      return _Engine(recognizer, stream);
    } catch (_) {
      stream?.free();
      recognizer.free();
      rethrow;
    }
  }

  final sherpa.OnlineRecognizer _recognizer;
  final sherpa.OnlineStream _stream;

  String get text => _recognizer.getResult(_stream).text.trim();

  bool add(Float32List samples, int sampleRate) {
    _stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    return _decodeAvailable();
  }

  String finish(int sampleRate) {
    // One 1120 ms encoder window of silence lets the model flush short tails.
    _stream.acceptWaveform(
      samples: Float32List(sampleRate * 112 ~/ 100),
      sampleRate: sampleRate,
    );
    _stream.inputFinished();
    _decodeAvailable();
    return text;
  }

  bool _decodeAvailable() {
    var decoded = false;
    while (_recognizer.isReady(_stream)) {
      _recognizer.decode(_stream);
      decoded = true;
    }
    return decoded;
  }

  void close() {
    _stream.free();
    _recognizer.free();
  }
}

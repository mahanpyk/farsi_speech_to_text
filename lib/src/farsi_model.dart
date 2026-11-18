import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const encoderName = 'encoder.int8.onnx';
const decoderName = 'decoder.int8.onnx';
const joinerName = 'joiner.int8.onnx';
const tokensName = 'tokens.txt';

typedef _Asset = ({String name, int bytes, String hash});

const _origin =
    'https://huggingface.co/mentisialog/'
    'sherpa-onnx-nemotron-asr-streaming-farsi-1120ms-int8/resolve/'
    '773e3d8f6ce043100a5dff6083271aa7811299bd/';

const _assets = <_Asset>[
  (
    name: 'LICENSE',
    bytes: 2629,
    hash: 'be21b29b1c69af5b4a4e60a6bd7bc933eec374e52be29d1ebb9e6a17a6588491',
  ),
  (
    name: 'NOTICE',
    bytes: 1401,
    hash: 'aa6f023739a3398c8439955b6c568be47d2cf01a032dbb1062b8a78b65da7e70',
  ),
  (
    name: tokensName,
    bytes: 15037,
    hash: '7ace7d33f3784d50f9a46156cce7c411f39faab64b43df17bd5796abc56a3057',
  ),
  (
    name: decoderName,
    bytes: 7257753,
    hash: '548a4763366e3ba4ba5272f3d68465425f5c62b207922ee2d617be920a921b06',
  ),
  (
    name: joinerName,
    bytes: 1735861,
    hash: 'e5e365bd22a7f678899674ecad00a9fae23323973de73b508e54ea79eb56b3cc',
  ),
  (
    name: encoderName,
    bytes: 657573705,
    hash: '13c1d630f1c82a3534c76ff36a38b4823bdc2413254d5cf7489927b000d57aa2',
  ),
];

/// A missing, incomplete, or invalid Persian model file.
final class FarsiModelException extends FileSystemException {
  /// Identifies the model file that failed a check.
  const FarsiModelException(super.message, super.path);
}

/// The ONNX weights and tokenizer for the Persian Nemotron model.
final class FarsiModel {
  /// Uses [directory] as the location of the pinned model files.
  FarsiModel.at(Directory directory) : directory = directory.absolute;

  /// The directory that holds the model files and their license and notices.
  final Directory directory;

  Future<void>? _verified;
  Future<void>? _downloading;

  /// Checks whether all required files are present and have the expected sizes.
  ///
  /// Use [verify] to check their SHA-256 hashes before running inference.
  Future<bool> isInstalled() async {
    for (final asset in _assets) {
      if (!await _hasExpectedSize(_file(directory.path, asset), asset)) {
        return false;
      }
    }
    return true;
  }

  /// Verifies the integrity of the model files.
  ///
  /// Throws a [FarsiModelException] for a missing, truncated or corrupt file.
  /// Successful verification is cached for this instance. Use a fresh instance
  /// after replacing files in [directory].
  Future<void> verify() async {
    final path = directory.path;
    try {
      await (_verified ??= Isolate.run(() => _verifyFiles(path)));
    } catch (_) {
      _verified = null;
      rethrow;
    }
  }

  /// Downloads the pinned model and verifies its SHA-256 hashes.
  ///
  /// The download is about 666 MB. Existing verified files are reused on retry.
  /// [onProgress] receives the fraction of bytes available from zero to one.
  /// Concurrent calls on this instance share a download and its first callback.
  Future<void> download({void Function(double fraction)? onProgress}) async {
    if (_downloading case final existing?) return existing;
    final task = _install(onProgress);
    _downloading = task;
    try {
      await task;
    } finally {
      _downloading = null;
    }
  }

  Future<void> _install(void Function(double)? onProgress) async {
    await directory.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final total = _assets.fold(0, (count, asset) => count + asset.bytes);
    var complete = 0;
    try {
      onProgress?.call(0);
      for (final asset in _assets) {
        final path = _file(directory.path, asset).path;
        if (!await _matchesInBackground(path, asset)) {
          await _downloadAsset(client, path, asset, (bytes) {
            onProgress?.call((complete + bytes) / total);
          });
        }
        complete += asset.bytes;
        onProgress?.call(complete / total);
      }
      _verified = Future.value();
    } finally {
      client.close(force: true);
    }
  }
}

File _file(String directory, _Asset asset) =>
    File(p.join(directory, asset.name));

Future<bool> _hasExpectedSize(File file, _Asset asset) async {
  final stat = await file.stat();
  return stat.type == FileSystemEntityType.file && stat.size == asset.bytes;
}

Future<bool> _matches(String path, _Asset asset) async {
  final file = File(path);
  if (!await _hasExpectedSize(file, asset)) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == asset.hash;
}

Future<bool> _matchesInBackground(String path, _Asset asset) =>
    Isolate.run(() => _matches(path, asset));

Future<void> _verifyFiles(String directory) async {
  for (final asset in _assets) {
    final path = _file(directory, asset).path;
    if (!await _matches(path, asset)) {
      throw FarsiModelException('Missing or invalid Persian model file', path);
    }
  }
}

Future<void> _downloadAsset(
  HttpClient client,
  String path,
  _Asset asset,
  void Function(int) onProgress,
) async {
  final staging = await Directory(p.dirname(path)).createTemp('.download-');
  try {
    final temporary = _file(staging.path, asset);
    // Small requests let an interrupted encoder transfer resume in place.
    const maxRequestBytes = 32 * 1024 * 1024;
    final ranged = asset.bytes > maxRequestBytes;
    var offset = 0;
    var failures = 0;
    while (offset < asset.bytes) {
      final end = math.min(offset + maxRequestBytes, asset.bytes) - 1;
      try {
        await _downloadRange(
          client,
          temporary,
          asset,
          offset,
          end,
          ranged,
          onProgress,
        );
        offset = end + 1;
        failures = 0;
      } catch (error) {
        if (error is! IOException && error is! TimeoutException) rethrow;
        final available = ranged ? (await temporary.stat()).size : 0;
        failures = available > offset ? 0 : failures + 1;
        if (failures >= 3) rethrow;
        offset = available;
      }
    }
    if (!await _matchesInBackground(temporary.path, asset)) {
      throw FarsiModelException(
        'Model download failed SHA-256 verification',
        path,
      );
    }
    await temporary.rename(path);
  } finally {
    await staging.delete(recursive: true);
  }
}

Future<void> _downloadRange(
  HttpClient client,
  File temporary,
  _Asset asset,
  int start,
  int end,
  bool ranged,
  void Function(int) onProgress,
) async {
  final uri = Uri.parse('$_origin${asset.name}?download=true').replace(
    queryParameters: {'download': 'true', if (ranged) 'offset': '$start'},
  );
  final request = await client.getUrl(uri);
  if (ranged) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

  const timeout = Duration(seconds: 45);
  final response = await request.close().timeout(
    timeout,
    onTimeout: () {
      request.abort();
      throw TimeoutException('Model download response timed out', timeout);
    },
  );
  final expectedStatus = ranged ? HttpStatus.partialContent : HttpStatus.ok;
  if (response.statusCode != expectedStatus ||
      (ranged &&
          response.headers.value(HttpHeaders.contentRangeHeader) !=
              'bytes $start-$end/${asset.bytes}')) {
    unawaited(response.listen(null).cancel());
    throw HttpException(
      'Unexpected model download response (HTTP ${response.statusCode})',
      uri: uri,
    );
  }

  var received = start;
  final chunks = response.timeout(timeout).map((bytes) {
    received += bytes.length;
    if (received > end + 1) {
      throw FarsiModelException(
        'Model download exceeds expected size',
        temporary.path,
      );
    }
    onProgress(received);
    return bytes;
  });
  final sink = temporary.openWrite(
    mode: start == 0 ? FileMode.write : FileMode.append,
  );
  try {
    await sink.addStream(chunks);
  } finally {
    await sink.close();
  }
  if (received != end + 1) {
    throw HttpException(
      'Model download ended before the requested range',
      uri: uri,
    );
  }
}

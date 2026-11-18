import 'dart:io';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FarsiModel model;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('persian_model_test_');
    model = FarsiModel.at(directory);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('checks file digests even when every size matches', () async {
    for (final entry in {
      'LICENSE': 2629,
      'NOTICE': 1401,
      'tokens.txt': 15037,
      'decoder.int8.onnx': 7257753,
      'joiner.int8.onnx': 1735861,
      'encoder.int8.onnx': 657573705,
    }.entries) {
      final file = await File(
        '${directory.path}/${entry.key}',
      ).open(mode: FileMode.write);
      await file.truncate(entry.value);
      await file.close();
    }

    expect(await model.isInstalled(), isTrue);
    await expectLater(
      model.verify(),
      throwsA(
        isA<FarsiModelException>().having(
          (e) => e.path,
          'path',
          endsWith('/LICENSE'),
        ),
      ),
    );
  });

  test('discards a download with the right size and a wrong digest', () async {
    final requests = <String>[];
    server.listen((request) {
      requests.add(request.uri.path);
      request.response
        ..contentLength = 2629
        ..add(List.filled(2629, 0));
      request.response.close();
    });
    final client = _LocalClient(server.port);
    final progress = <double>[];

    await HttpOverrides.runZoned(() async {
      await expectLater(
        model.download(onProgress: progress.add),
        throwsA(isA<FarsiModelException>()),
      );
    }, createHttpClient: (_) => client);

    expect(requests, hasLength(1));
    expect(requests.single, endsWith('/LICENSE'));
    expect(progress, isNotEmpty);
    expect(progress.first, 0);
    expect(progress.last, greaterThan(0));
    expect(await directory.list().toList(), isEmpty);
  });

  test('retries a failed HTTP response and shares the download', () async {
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..close();
    });
    final client = _LocalClient(server.port);

    await HttpOverrides.runZoned(() async {
      final first = model.download();
      final second = model.download();
      await Future.wait([
        expectLater(first, throwsA(isA<HttpException>())),
        expectLater(second, throwsA(isA<HttpException>())),
      ]);
    }, createHttpClient: (_) => client);

    expect(requests, 3);
    expect(await directory.list().toList(), isEmpty);
  });
}

final class _LocalClient implements HttpClient {
  _LocalClient(this.port);

  final int port;
  final HttpClient _client = HttpClient();

  @override
  set connectionTimeout(Duration? timeout) =>
      _client.connectionTimeout = timeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _client.getUrl(
    url.replace(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
    ),
  );

  @override
  void close({bool force = false}) => _client.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

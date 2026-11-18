import 'dart:typed_data';

import 'package:farsi_speech_to_text/farsi_speech_to_text.dart';
import 'package:farsi_speech_to_text_example/demo_backend.dart';
import 'package:farsi_speech_to_text_example/main.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows a setup failure and keeps recognition unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      FarsiDemo(
        locateBackend: () async => throw StateError('Storage unavailable'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Storage unavailable'), findsOneWidget);
    final record = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'شروع ضبط'),
    );
    expect(record.onPressed, isNull);
  });

  testWidgets('enables recording after preparing and disposes the backend', (
    tester,
  ) async {
    final backend = _DemoBackend();
    await tester.pumpWidget(FarsiDemo(locateBackend: () async => backend));
    await tester.pumpAndSettle();
    final recordButton = find.widgetWithText(FilledButton, 'شروع ضبط');
    expect(tester.widget<FilledButton>(recordButton).onPressed, isNull);

    await tester.tap(find.text('آماده‌سازی مدل'));
    await tester.pumpAndSettle();

    expect(backend.prepareCount, 1);
    expect(tester.widget<FilledButton>(recordButton).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(backend.disposed, isTrue);
  });
}

class _DemoBackend implements DemoBackend {
  var prepareCount = 0;
  var disposed = false;

  @override
  Future<bool> isPrepared() async => false;

  @override
  Future<void> prepare({required void Function(double) onProgress}) async {
    prepareCount++;
    onProgress(1);
  }

  @override
  Future<String> transcribeFile(XFile file) async => '';

  @override
  Stream<FarsiTranscript> transcribePcm16(Stream<Uint8List> audio) =>
      const Stream.empty();

  @override
  void dispose() => disposed = true;
}

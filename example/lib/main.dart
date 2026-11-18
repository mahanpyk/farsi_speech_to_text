import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart';

import 'demo_backend.dart';
import 'demo_backend_native.dart'
    if (dart.library.js_interop) 'demo_backend_web.dart';

void main() => runApp(const FarsiDemo());

class FarsiDemo extends StatelessWidget {
  const FarsiDemo({super.key, this.locateBackend = createBackend});

  final Future<DemoBackend> Function() locateBackend;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'گفتار فارسی به متن',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF146C60)),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: _TranscriptionPage(locateBackend: locateBackend),
    ),
  );
}

enum _Phase { checking, idle, downloading, opening, recording, finishing, file }

class _TranscriptionPage extends StatefulWidget {
  const _TranscriptionPage({required this.locateBackend});

  final Future<DemoBackend> Function() locateBackend;

  @override
  State<_TranscriptionPage> createState() => _TranscriptionPageState();
}

class _TranscriptionPageState extends State<_TranscriptionPage> {
  AudioRecorder? _recorder;
  DemoBackend? _backend;
  _Phase _phase = _Phase.checking;
  bool _ready = false;
  double _progress = 0;
  String _transcript = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_checkModel());
  }

  @override
  void dispose() {
    if (_recorder case final recorder?) unawaited(recorder.dispose());
    _backend?.dispose();
    super.dispose();
  }

  Future<void> _checkModel() async {
    await _run(_Phase.checking, () async {
      final backend = await widget.locateBackend();
      if (!mounted) {
        backend.dispose();
        return;
      }
      _backend = backend;
      final installed = await backend.isPrepared();
      if (mounted) setState(() => _ready = installed);
    });
  }

  Future<void> _download() async {
    await _run(_Phase.downloading, () async {
      await _backend!.prepare(
        onProgress: (fraction) {
          final nextPercent = (fraction * 100).floor() / 100;
          if (mounted && nextPercent != _progress) {
            setState(() => _progress = nextPercent);
          }
        },
      );
      if (mounted) setState(() => _ready = true);
    });
  }

  Future<void> _openFile() async {
    await _run(_Phase.file, () async {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'WAV audio',
            extensions: ['wav'],
            uniformTypeIdentifiers: ['com.microsoft.waveform-audio'],
            mimeTypes: ['audio/wav', 'audio/x-wav'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      setState(() => _transcript = '');
      final transcript = await _backend!.transcribeFile(file);
      if (mounted) setState(() => _transcript = transcript);
    });
  }

  Future<void> _startRecording() async {
    await _run(_Phase.opening, () async {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw StateError('دسترسی میکروفون را در تنظیمات دستگاه فعال کنید.');
      }
      if (!mounted) return;
      setState(() => _transcript = '');

      try {
        await for (final result in _backend!.transcribePcm16(
          _microphone(recorder),
        )) {
          if (!mounted) break;
          setState(() => _transcript = result.text);
        }
      } finally {
        if (mounted && await recorder.isRecording()) await recorder.stop();
      }
    });
  }

  Stream<Uint8List> _microphone(AudioRecorder recorder) async* {
    if (!mounted) return;
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.recording);
    yield* stream;
  }

  Future<void> _stopRecording() async {
    setState(() => _phase = _Phase.finishing);
    try {
      await _recorder!.stop();
    } catch (error) {
      if (mounted && _phase == _Phase.finishing) {
        setState(() {
          _phase = _Phase.recording;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _run(_Phase phase, Future<void> Function() action) async {
    setState(() {
      _error = null;
      _phase = phase;
      if (phase == _Phase.downloading) _progress = 0;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        if (needsModelPreparation(error)) {
          _ready = false;
        }
      });
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  String get _status => switch (_phase) {
    _Phase.checking => 'در حال بررسی مدل…',
    _Phase.downloading => 'آماده‌سازی مدل… ${(_progress * 100).round()}٪',
    _Phase.opening => 'در حال آماده‌سازی میکروفون…',
    _Phase.recording => 'در حال ضبط',
    _Phase.finishing => 'در حال تکمیل متن…',
    _Phase.file => 'در حال باز کردن یا پردازش فایل…',
    _Phase.idle when _ready => 'آمادهٔ تبدیل آفلاین',
    _Phase.idle when _backend != null =>
      'آماده‌سازی مدل · دانلود اولیه حدود ۶۶۶ مگابایت',
    _Phase.idle => 'پوشهٔ مدل در دسترس نیست',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final idle = _phase == _Phase.idle;
    final recording = _phase == _Phase.recording;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'گفتار فارسی به متن',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(_status),
                if (_phase == _Phase.downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_ready && _backend != null)
                      FilledButton.tonalIcon(
                        onPressed: idle ? _download : null,
                        icon: const Icon(Icons.download),
                        label: const Text('آماده‌سازی مدل'),
                      ),
                    FilledButton.icon(
                      onPressed: recording
                          ? _stopRecording
                          : idle && _ready
                          ? _startRecording
                          : null,
                      icon: Icon(recording ? Icons.stop : Icons.mic_none),
                      label: Text(recording ? 'توقف ضبط' : 'شروع ضبط'),
                    ),
                    OutlinedButton.icon(
                      onPressed: idle && _ready ? _openFile : null,
                      icon: const Icon(Icons.audio_file_outlined),
                      label: const Text('انتخاب فایل WAV'),
                    ),
                  ],
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: colors.error)),
                ],
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('متن')),
                            IconButton(
                              onPressed: _transcript.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: _transcript),
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('متن کپی شد'),
                                        ),
                                      );
                                    },
                              tooltip: 'کپی متن',
                              icon: const Icon(Icons.copy_outlined),
                            ),
                          ],
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 120),
                          child: SelectableText(
                            _transcript.isEmpty
                                ? 'متنِ گفتار اینجا نمایش داده می‌شود.'
                                : _transcript,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

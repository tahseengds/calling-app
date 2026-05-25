import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/theme/app_colors.dart';

/// Hold-to-record mic button. Slide left to cancel. Releases with the
/// recorded file, or null if the user cancelled.
class VoiceNoteRecorder extends StatefulWidget {
  final void Function(File file, int durationSeconds) onSend;

  const VoiceNoteRecorder({super.key, required this.onSend});

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder>
    with SingleTickerProviderStateMixin {
  final _recorder = FlutterSoundRecorder();
  bool _recording = false;
  bool _cancelled = false;
  int _seconds = 0;
  Timer? _timer;
  String? _filePath;
  late final AnimationController _pulseCtrl;
  double _dragX = 0;

  static const _cancelThreshold = -80.0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timer?.cancel();
    _recorder.closeRecorder();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) return;

    await _recorder.openRecorder();
    final dir = await getTemporaryDirectory();
    _filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

    await _recorder.startRecorder(toFile: _filePath);
    _seconds = 0;
    _cancelled = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    _timer?.cancel();
    await _recorder.stopRecorder();
    await _recorder.closeRecorder();

    if (!cancel && !_cancelled && _filePath != null && _seconds >= 1) {
      widget.onSend(File(_filePath!), _seconds);
    }
    setState(() {
      _recording = false;
      _dragX = 0;
    });
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_recording) return _buildRecordingBar();
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      onLongPressMoveUpdate: (d) {
        setState(() => _dragX = d.localPosition.dx);
        if (_dragX < _cancelThreshold && !_cancelled) {
          _cancelled = true;
          _stopRecording(cancel: true);
        }
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 22),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08 + _pulseCtrl.value * 0.06),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Icon(Icons.mic_rounded,
                color: AppColors.danger.withValues(alpha: 0.8 + _pulseCtrl.value * 0.2),
                size: 20),
            const SizedBox(width: 8),
            Text(
              _fmt(_seconds),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger),
            ),
            const Spacer(),
            const Text(
              '← slide to cancel',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

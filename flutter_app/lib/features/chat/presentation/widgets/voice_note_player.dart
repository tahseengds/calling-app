import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../../../core/theme/app_colors.dart';

class VoiceNotePlayer extends StatefulWidget {
  final String url;
  final int? durationSeconds;
  final bool isSent; // affects color scheme

  const VoiceNotePlayer({
    super.key,
    required this.url,
    this.durationSeconds,
    this.isSent = false,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = FlutterSoundPlayer();
  bool _isPlaying = false;
  double _progress = 0;
  int _elapsed = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _player.openPlayer().then((_) {
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_initialized) return;
    if (_isPlaying) {
      await _player.pausePlayer();
      setState(() => _isPlaying = false);
    } else {
      await _player.startPlayer(
        fromURI: widget.url,
        whenFinished: () {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _progress = 0;
              _elapsed = 0;
            });
          }
        },
      );
      _player.onProgress!.listen((e) {
        if (!mounted) return;
        final total = e.duration.inMilliseconds;
        final pos = e.position.inMilliseconds;
        setState(() {
          _elapsed = e.position.inSeconds;
          _progress = total > 0 ? pos / total : 0;
        });
      });
      setState(() => _isPlaying = true);
    }
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.durationSeconds ?? 0;
    final fg = widget.isSent ? Colors.white : AppColors.primary;
    final trackColor =
        widget.isSent ? Colors.white.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.2);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: fg,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: trackColor,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_fmt(_elapsed)} / ${_fmt(total)}',
                style: TextStyle(
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Outgoing-call ringback tone — what the *caller* hears while the callee's
// phone is ringing. This is the classic North American dual-tone (440 +
// 480 Hz, 2 s on / 4 s off). Generated in-process as a 16-bit mono WAV
// buffer so no audio asset needs to ship with the app.
//
// Why generate instead of bundling an mp3? An mp3 ringback adds ~30 KB
// to the APK and a hot-path asset load on every call; the WAV is tiny
// (~258 KB in RAM, computed once at first use) and starts playing the
// frame it's requested. The dual-tone is also a well-known standard,
// so synthesising it directly avoids "which copyright?" questions.

import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
// flutter/foundation.dart re-exports dart:typed_data's ByteData/Uint8List —
// keep the import here instead of an explicit dart:typed_data line.
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RingbackPlayer {
  static const int _sampleRate = 22050;
  static const int _onSeconds = 2;
  static const int _offSeconds = 4;

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Future<String>? _tonePathFuture;

  /// Start the ringback loop. Safe to call multiple times — second call
  /// while already playing is a no-op.
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      final path = await _ensureTone();
      // ── Audio routing ─────────────────────────────────────────────────────
      // VoIP behavior: ringback plays through the EARPIECE on audio calls,
      // not the loudspeaker, because the user typically has the phone to
      // their ear by the time the callee picks up. If they want to hear it
      // out loud they can toggle speakerphone from the call UI.
      //
      //   - voiceCommunicationSignalling = canonical Android usage for
      //     ringback / call-progress tones. Routes through the voice-call
      //     stream so STREAM_VOICE_CALL volume keys control it.
      //   - isSpeakerphoneOn: false = earpiece (overridable by user toggle).
      //   - gainTransient = brief, low-priority focus that doesn't disrupt
      //     other audio.
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.voiceCommunicationSignalling,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
            },
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      // Moderate volume — STREAM_VOICE_CALL is fairly loud at its max, and
      // the user can adjust with the volume rocker.
      await _player.setVolume(0.8);
      final fileSize = await File(path).length();
      debugPrint('[ringback] starting (file=$path, $fileSize bytes)');
      // Play from the cached temp file. DeviceFileSource loops cleanly on
      // both Android and iOS, where BytesSource sometimes restarts with a
      // gap on platform-specific buffer boundaries.
      await _player.play(DeviceFileSource(path));
      debugPrint('[ringback] play() returned ok');
    } catch (e, st) {
      debugPrint('[ringback] start failed: $e\n$st');
      _playing = false;
    }
  }

  /// Stop and rewind. Safe to call when not playing.
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _player.stop();
    } catch (e) {
      // Stop is best-effort — the player may already be torn down.
      debugPrint('[ringback] stop failed: $e');
    }
  }

  Future<void> dispose() async {
    _playing = false;
    try {
      await _player.dispose();
    } catch (_) {}
  }

  /// Lazy-build the WAV file on disk the first time it's needed. Subsequent
  /// calls return the cached path. The file goes to the OS temp dir, so it
  /// disappears with the next app restart — that's fine; we'll regenerate.
  Future<String> _ensureTone() async {
    final pending = _tonePathFuture;
    if (pending != null) return pending;
    final future = () async {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lumio_ringback.wav');
      if (!await file.exists()) {
        final bytes = _generateRingbackWav();
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    }();
    _tonePathFuture = future;
    return future;
  }

  /// Build a 6 s WAV: 2 s of (440 Hz + 480 Hz) mix, then 4 s of silence.
  /// 16-bit mono PCM @ 22 050 Hz. Total ~258 KB.
  static Uint8List _generateRingbackWav() {
    const totalSeconds = _onSeconds + _offSeconds;
    final totalSamples = _sampleRate * totalSeconds;
    final dataBytes = totalSamples * 2; // 16-bit mono
    final fileSize = 36 + dataBytes;

    final buf = ByteData(44 + dataBytes);
    // RIFF / WAVE header — see http://soundfile.sapp.org/doc/WaveFormat/
    buf.setUint8(0, 0x52); buf.setUint8(1, 0x49);
    buf.setUint8(2, 0x46); buf.setUint8(3, 0x46); // 'RIFF'
    buf.setUint32(4, fileSize, Endian.little);
    buf.setUint8(8, 0x57); buf.setUint8(9, 0x41);
    buf.setUint8(10, 0x56); buf.setUint8(11, 0x45); // 'WAVE'
    buf.setUint8(12, 0x66); buf.setUint8(13, 0x6D);
    buf.setUint8(14, 0x74); buf.setUint8(15, 0x20); // 'fmt '
    buf.setUint32(16, 16, Endian.little);   // fmt-chunk size
    buf.setUint16(20, 1, Endian.little);    // PCM
    buf.setUint16(22, 1, Endian.little);    // mono
    buf.setUint32(24, _sampleRate, Endian.little);
    buf.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
    buf.setUint16(32, 2, Endian.little);    // block align (1 ch × 16 bit / 8)
    buf.setUint16(34, 16, Endian.little);   // bits per sample
    buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74); buf.setUint8(39, 0x61); // 'data'
    buf.setUint32(40, dataBytes, Endian.little);

    // Synthesise samples.
    final onSamples = _sampleRate * _onSeconds;
    const twoPi = 2 * math.pi;
    // Two sines summed and scaled. Each at ~0.3 peak so the sum stays
    // inside ±1.0 with margin; then multiplied up to 16-bit range.
    const peak = 0.3;
    for (int i = 0; i < totalSamples; i++) {
      int sample = 0;
      if (i < onSamples) {
        final t = i / _sampleRate;
        // 10 ms fade-in / fade-out on the on-segment to avoid a click on
        // every loop start. Fade window is per-on-segment, not the whole
        // file.
        const fadeSamples = 220; // ~10 ms at 22050 Hz
        double env = 1.0;
        if (i < fadeSamples) {
          env = i / fadeSamples;
        } else if (i > onSamples - fadeSamples) {
          env = (onSamples - i) / fadeSamples;
        }
        final s = peak *
            env *
            (math.sin(twoPi * 440 * t) + math.sin(twoPi * 480 * t));
        sample = (s * 32767).round().clamp(-32768, 32767);
      }
      buf.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buf.buffer.asUint8List();
  }
}

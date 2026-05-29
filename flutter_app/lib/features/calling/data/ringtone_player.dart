// Incoming-call ringtone — what the *callee* hears while their phone rings.
//
// Counterpart to [RingbackPlayer] (which is what the caller hears). The key
// differences: this plays through the LOUDSPEAKER (the callee isn't holding
// the phone to their ear yet), on the ringtone stream, at full volume, with a
// faster 1 s-on / 2 s-off ring cadence. Like the ringback, the tone is
// synthesised in-process to a small WAV so no audio asset ships with the app.

import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RingtonePlayer {
  static const int _sampleRate = 22050;
  static const int _onSeconds = 1;
  static const int _offSeconds = 2;

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Future<String>? _tonePathFuture;

  /// Start the ringtone loop. Safe to call multiple times — a second call
  /// while already playing is a no-op.
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      final path = await _ensureTone();
      // Route to the LOUDSPEAKER on the ringtone stream so the callee hears
      // it across the room, and so the hardware volume keys map to the ring
      // volume rather than the in-call stream.
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      final fileSize = await File(path).length();
      debugPrint('[ringtone] starting (file=$path, $fileSize bytes)');
      await _player.play(DeviceFileSource(path));
      debugPrint('[ringtone] play() returned ok');
    } catch (e, st) {
      debugPrint('[ringtone] start failed: $e\n$st');
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
      debugPrint('[ringtone] stop failed: $e');
    }
  }

  Future<void> dispose() async {
    _playing = false;
    try {
      await _player.dispose();
    } catch (_) {}
  }

  /// Lazy-build the WAV the first time it's needed; cache the path after.
  Future<String> _ensureTone() async {
    final pending = _tonePathFuture;
    if (pending != null) return pending;
    final future = () async {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lumio_ringtone.wav');
      if (!await file.exists()) {
        await file.writeAsBytes(_generateRingtoneWav(), flush: true);
      }
      return file.path;
    }();
    _tonePathFuture = future;
    return future;
  }

  /// Build a 3 s WAV: 1 s of (440 Hz + 480 Hz) mix, then 2 s of silence.
  /// 16-bit mono PCM @ 22 050 Hz. Loops into the classic phone-ring cadence.
  static Uint8List _generateRingtoneWav() {
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
    buf.setUint16(32, 2, Endian.little);    // block align
    buf.setUint16(34, 16, Endian.little);   // bits per sample
    buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74); buf.setUint8(39, 0x61); // 'data'
    buf.setUint32(40, dataBytes, Endian.little);

    final onSamples = _sampleRate * _onSeconds;
    const twoPi = 2 * math.pi;
    const peak = 0.3; // same headroom as the ringback (sum stays inside ±1.0)
    for (int i = 0; i < totalSamples; i++) {
      int sample = 0;
      if (i < onSamples) {
        final t = i / _sampleRate;
        // 10 ms fade in/out on the on-segment to avoid a click on loop start.
        const fadeSamples = 220;
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

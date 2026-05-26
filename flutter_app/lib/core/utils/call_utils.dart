// SDP and ICE utility helpers for the WebRTC calling layer (Prompt 14).

/// Format [seconds] as MM:SS display string.
String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Insert `b=AS:<kbps>` bitrate-cap lines into an SDP string.
///
/// Inserts [videoKbps] immediately after the first `c=IN` line in the video
/// section and [audioKbps] after the first `c=IN` line in the audio section.
/// Returns [sdp] unchanged if the relevant section is not found.
String applyBitrateCap(
  String sdp, {
  int videoKbps = 800,
  int audioKbps = 50,
}) {
  final lines = sdp.split('\r\n');
  final result = <String>[];
  var section = ''; // 'audio' | 'video' | ''
  var bitrateInserted = false;

  for (final line in lines) {
    if (line.startsWith('m=video')) {
      section = 'video';
      bitrateInserted = false;
    } else if (line.startsWith('m=audio')) {
      section = 'audio';
      bitrateInserted = false;
    } else if (line.startsWith('m=')) {
      section = '';
    }

    result.add(line);

    if (!bitrateInserted && line.startsWith('c=IN')) {
      if (section == 'video') {
        result.add('b=AS:$videoKbps');
        bitrateInserted = true;
      } else if (section == 'audio') {
        result.add('b=AS:$audioKbps');
        bitrateInserted = true;
      }
    }
  }

  return result.join('\r\n');
}

/// Re-order codec payload types on each `m=` line so that preferred codecs
/// appear first.
///
/// - Audio: prefers OPUS/48000.
/// - Video: prefers H.264, then VP8; deprioritises VP9 and AV1.
String preferCodecs(String sdp) {
  var result = sdp;
  // Prefer OPUS for audio
  result = _moveCodecToFront(result, 'm=audio', 'opus/48000');
  // Prefer H.264 for video; fall back to VP8
  final withH264 = _moveCodecToFront(result, 'm=video', 'h264');
  result = withH264 != result
      ? withH264
      : _moveCodecToFront(result, 'm=video', 'vp8');
  return result;
}

// ── Private helpers ────────────────────────────────────────────────────────

String _moveCodecToFront(
    String sdp, String mLinePrefix, String rtpmapPattern) {
  final lines = sdp.split('\r\n');
  String? targetPt;

  for (final line in lines) {
    if (!line.startsWith('a=rtpmap:')) {
      continue;
    }
    final content = line.substring('a=rtpmap:'.length);
    final spaceIdx = content.indexOf(' ');
    if (spaceIdx <= 0) {
      continue;
    }
    final pt = content.substring(0, spaceIdx);
    final codec = content.substring(spaceIdx + 1).toLowerCase();
    if (codec.contains(rtpmapPattern.toLowerCase())) {
      targetPt = pt;
      break;
    }
  }

  if (targetPt == null) {
    return sdp;
  }

  return sdp.replaceFirstMapped(
    RegExp('(${RegExp.escape(mLinePrefix)}[^\r\n]+)'),
    (match) {
      final mLine = match[1]!;
      final parts = mLine.split(' ');
      if (parts.length < 4) {
        return mLine;
      }
      final prefix = parts.sublist(0, 3).join(' ');
      final pts = parts.sublist(3);
      if (!pts.contains(targetPt)) {
        return mLine;
      }
      final reordered = [targetPt!, ...pts.where((p) => p != targetPt)];
      return '$prefix ${reordered.join(' ')}';
    },
  );
}

// TODO: prompt 13 — media upload helpers (MIME detection, thumbnail extraction)

String? mimeFromExtension(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'pdf': 'application/pdf',
  };
  return map[ext];
}

bool isImage(String? mimeType) => mimeType?.startsWith('image/') ?? false;
bool isVideo(String? mimeType) => mimeType?.startsWith('video/') ?? false;
bool isAudio(String? mimeType) => mimeType?.startsWith('audio/') ?? false;

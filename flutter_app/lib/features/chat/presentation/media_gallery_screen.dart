import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

/// One item in the full-screen gallery. [url] may be a remote http(s) URL or a
/// local file path (for media that hasn't finished uploading yet).
class GalleryMediaItem {
  final String url;
  final bool isVideo;

  const GalleryMediaItem({required this.url, required this.isVideo});

  bool get isNetwork =>
      url.startsWith('http://') || url.startsWith('https://');

  /// Local filesystem path (strips a `file://` scheme if present).
  String get filePath =>
      url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
}

/// Full-screen, swipeable media viewer for one or more photos/videos.
/// - images: pinch-zoom via photo_view, swipe between items
/// - videos: tap-to-play VideoPlayer with scrubber
class MediaGalleryScreen extends StatefulWidget {
  final List<GalleryMediaItem> items;
  final int initialIndex;
  final String? sender;

  const MediaGalleryScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.sender,
  });

  /// Convenience launcher used from the chat bubbles.
  static Future<void> open(
    BuildContext context, {
    required List<GalleryMediaItem> items,
    int initialIndex = 0,
    String? sender,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MediaGalleryScreen(
          items: items,
          initialIndex: initialIndex,
          sender: sender,
        ),
      ),
    );
  }

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.items.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.sender != null)
              Text(widget.sender!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            if (multiple)
              Text('${_index + 1} of ${widget.items.length}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12)),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final item = widget.items[i];
          if (item.isVideo) {
            return _GalleryVideoPage(item: item, isActive: i == _index);
          }
          return _GalleryImagePage(item: item);
        },
      ),
    );
  }
}

class _GalleryImagePage extends StatelessWidget {
  final GalleryMediaItem item;
  const _GalleryImagePage({required this.item});

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider = item.isNetwork
        ? CachedNetworkImageProvider(item.url)
        : FileImage(File(item.filePath));
    return PhotoView(
      imageProvider: provider,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, _) => const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      ),
    );
  }
}

class _GalleryVideoPage extends StatefulWidget {
  final GalleryMediaItem item;
  final bool isActive;
  const _GalleryVideoPage({required this.item, required this.isActive});

  @override
  State<_GalleryVideoPage> createState() => _GalleryVideoPageState();
}

class _GalleryVideoPageState extends State<_GalleryVideoPage> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = widget.item.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.item.url))
        : VideoPlayerController.file(File(widget.item.filePath));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.isActive) ctrl.play();
    } catch (_) {
      // Leave _ready false — the loader stays, no crash.
    }
  }

  @override
  void didUpdateWidget(_GalleryVideoPage old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    // Pause when swiped away; resume when swiped back.
    if (!widget.isActive && (_ctrl?.value.isPlaying ?? false)) {
      _ctrl?.pause();
    } else if (widget.isActive && !old.isActive) {
      _ctrl?.play();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (!_ready || ctrl == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
          if (_showControls) ...[
            GestureDetector(
              onTap: () => setState(() {
                ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
              }),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ctrl.value.isPlaying
                      ? LucideIcons.pause
                      : LucideIcons.play,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: VideoProgressIndicator(
                ctrl,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white.withValues(alpha: 0.3),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

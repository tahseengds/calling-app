import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

/// Full-screen media viewer.
/// - image: pinch-zoom via photo_view
/// - video: VideoPlayer with play/pause controls
class MediaViewerScreen extends StatefulWidget {
  final String url;
  final String kind; // 'image' | 'video'
  final String? sender;
  final String? when;

  const MediaViewerScreen({
    super.key,
    required this.url,
    required this.kind,
    this.sender,
    this.when,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  VideoPlayerController? _vpCtrl;
  bool _videoInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    if (widget.kind == 'video') _initVideo();
  }

  Future<void> _initVideo() async {
    final ctrl =
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _vpCtrl = ctrl;
    await ctrl.initialize();
    if (mounted) {
      setState(() => _videoInitialized = true);
      ctrl.play();
    }
  }

  @override
  void dispose() {
    _vpCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
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
            if (widget.when != null)
              Text(widget.when!,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: widget.kind == 'image' ? _buildImage() : _buildVideo(),
    );
  }

  Widget _buildImage() {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(widget.url),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) => const Center(
        child: CircularProgressIndicator(
          color: Colors.white54,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildVideo() {
    if (!_videoInitialized || _vpCtrl == null) {
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
              aspectRatio: _vpCtrl!.value.aspectRatio,
              child: VideoPlayer(_vpCtrl!),
            ),
          ),
          if (_showControls) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _vpCtrl!.value.isPlaying
                      ? _vpCtrl!.pause()
                      : _vpCtrl!.play();
                });
              },
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _vpCtrl!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
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
                _vpCtrl!,
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

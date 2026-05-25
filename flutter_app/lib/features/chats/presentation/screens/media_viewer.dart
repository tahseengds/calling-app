import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/lumio_icons.dart';

class MediaViewer extends StatefulWidget {
  final String kind; // 'image', 'video', 'document', 'audio'
  final String sender;
  final String when;
  /// Remote URL for the media file.  Null in UI-only / preview mode — the
  /// widget falls back to placeholder art when this is not supplied.
  final String? url;

  const MediaViewer({
    super.key,
    required this.kind,
    this.sender = 'Grandma Rose',
    this.when = 'Today · 7:42 PM',
    this.url,
  });

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  final double _videoProgress = 0.38;
  bool _isPlaying = true;
  int _docPage = 1;

  @override
  Widget build(BuildContext context) {
    final isDoc = widget.kind == 'document';
    final bg = isDoc ? const Color(0xFFF4F6FB) : const Color(0xFF0B0F1A);
    final fg = isDoc ? const Color(0xFF1A2235) : Colors.white;
    final fg2 = isDoc ? const Color(0xFF6B7488) : Colors.white.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // ── Media Content Body ──────────────────────────────────────────
          Positioned.fill(
            child: _buildMediaBody(widget.kind),
          ),

          // ── Top Action Bar ─────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 44, 8, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDoc
                      ? [
                          const Color(0xFFF4F6FB).withValues(alpha: 0.95),
                          const Color(0xFFF4F6FB).withValues(alpha: 0),
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0),
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LumioIcons.back, color: fg),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.kind == 'document' ? 'Family-tree-2026.pdf' : widget.sender,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.kind == 'document' ? '2.1 MB · Page 1 of 14' : widget.when,
                          style: TextStyle(
                            fontSize: 12,
                            color: fg2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(LumioIcons.more, color: fg),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom Action Controls ──────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(widget.kind, fg, fg2),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaBody(String kind) {
    if (kind == 'image') {
      return Center(
        child: Container(
          width: 320,
          height: 430,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 60,
                offset: Offset(0, 24),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.url != null
                ? CachedNetworkImage(
                    imageUrl: widget.url!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const _MediaLoadingPlaceholder(),
                    errorWidget: (_, __, ___) =>
                        CustomPaint(painter: _ImageArtPainter()),
                  )
                : CustomPaint(painter: _ImageArtPainter()),
          ),
        ),
      );
    } else if (kind == 'video') {
      // TODO(prompt-13): wire VideoPlayerController when backend sends signed URLs.
      return Center(
        child: Container(
          width: 340,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(painter: _VideoArtPainter()),
          ),
        ),
      );
    } else if (kind == 'audio') {
      // Audio has no visual preview — show waveform placeholder.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audiotrack_rounded,
                color: Colors.white.withValues(alpha: 0.7), size: 72),
            const SizedBox(height: 16),
            Text(
              widget.sender,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    } else {
      // document
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 76, bottom: 90, left: 24, right: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            height: 460,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE3E7F0)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A2235).withValues(alpha: 0.10),
                  blurRadius: 60,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The Martinez Family Tree',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A2235),
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'REVISED MARCH 2026',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF6B7488),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: CustomPaint(
                      size: const Size(220, 220),
                      painter: _DocumentTreePainter(),
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE3E7F0)),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Page 1 of 14',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7488)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildBottomBar(String kind, Color fg, Color fg2) {
    if (kind == 'video') {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.black.withValues(alpha: 0),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scrubber
            Row(
              children: [
                const SizedBox(
                  width: 36,
                  child: Text(
                    '0:18',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 14,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: _videoProgress,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment(_videoProgress * 2 - 1, 0),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '0:47',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white, size: 28),
                  onPressed: () {},
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isPlaying = !_isPlaying;
                    });
                  },
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0B0F1A),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(LumioIcons.speaker, color: Colors.white, size: 24),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      );
    } else if (kind == 'document') {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF4F6FB).withValues(alpha: 0.95),
              const Color(0xFFF4F6FB).withValues(alpha: 0),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDocNavButton(
              icon: LumioIcons.back,
              onTap: () {
                if (_docPage > 1) setState(() => _docPage--);
              },
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE3E7F0)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$_docPage / 14',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2235),
                ),
              ),
            ),
            const SizedBox(width: 14),
            _buildDocNavButton(
              icon: LumioIcons.chevronRight,
              onTap: () {
                if (_docPage < 14) setState(() => _docPage++);
              },
            ),
            const SizedBox(width: 12),
            _buildDocNavButton(
              icon: Icons.share_outlined,
              color: AppColors.primary,
              onTap: () {},
            ),
          ],
        ),
      );
    } else {
      // image - shows instruction
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: 28),
          child: Text(
            'Pinch to zoom · Swipe to dismiss',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white30,
              letterSpacing: 0.4,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildDocNavButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = const Color(0xFF1A2235),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFCDD4E1)),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

// ── Loading placeholder shown while CachedNetworkImage fetches the URL ──────
class _MediaLoadingPlaceholder extends StatelessWidget {
  const _MediaLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _ImageArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fill Gradient
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF7A93FB), Color(0xFF5B7CFA), Color(0xFF1A2235)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Sun/Moon
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.25),
      36,
      Paint()..color = const Color(0xFFFFD66B),
    );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.25),
      48,
      Paint()..color = const Color(0xFFFFD66B).withValues(alpha: 0.18),
    );

    // Mountains
    final path1 = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.22, size.height * 0.58, size.width * 0.5, size.height * 0.67)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.75, size.width, size.height * 0.625)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path1, Paint()..color = const Color(0xFF0F1525).withValues(alpha: 0.55));

    final path2 = Path()
      ..moveTo(0, size.height * 0.83)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.71, size.width * 0.55, size.height * 0.77)
      ..quadraticBezierTo(size.width * 0.8, size.height * 0.83, size.width, size.height * 0.75)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.85));

    // Silhouettes
    final silhouettePaint = Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.9);
    // Person 1
    canvas.drawCircle(Offset(size.width * 0.33, size.height * 0.77), 18, silhouettePaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.33 - 20, size.height * 0.77 + 16, 40, 50),
        const Radius.circular(14),
      ),
      silhouettePaint,
    );

    // Person 2
    canvas.drawCircle(Offset(size.width * 0.47, size.height * 0.79), 14, silhouettePaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.47 - 14, size.height * 0.79 + 12, 28, 40),
        const Radius.circular(10),
      ),
      silhouettePaint,
    );

    // Person 3
    canvas.drawCircle(Offset(size.width * 0.58, size.height * 0.775), 20, silhouettePaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.58 - 22, size.height * 0.775 + 18, 44, 54),
        const Radius.circular(14),
      ),
      silhouettePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VideoArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fill Gradient
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3D4C72), Color(0xFF0B0F1A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Wave
    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(size.width * 0.18, size.height * 0.5, size.width * 0.38, size.height * 0.6)
      ..quadraticBezierTo(size.width * 0.75, size.height * 0.75, size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.6));

    // Sun/Moon
    canvas.drawCircle(
      Offset(size.width * 0.79, size.height * 0.25),
      22,
      Paint()..color = const Color(0xFFFFD66B).withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DocumentTreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF1A2235)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFFF0F3FA)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFF1A2235)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    // Draw tree branches
    canvas.drawLine(const Offset(110, 40), const Offset(55, 100), linePaint);
    canvas.drawLine(const Offset(110, 40), const Offset(165, 100), linePaint);
    
    canvas.drawLine(const Offset(55, 116), const Offset(28, 165), linePaint);
    canvas.drawLine(const Offset(55, 116), const Offset(82, 165), linePaint);

    canvas.drawLine(const Offset(165, 116), const Offset(138, 165), linePaint);
    canvas.drawLine(const Offset(165, 116), const Offset(192, 165), linePaint);

    // Draw nodes
    // Root
    canvas.drawCircle(const Offset(110, 40), 14, fillPaint);
    canvas.drawCircle(const Offset(110, 40), 14, borderPaint);
    _drawLetter(canvas, const Offset(110, 40), 'R');

    // Layer 1
    canvas.drawCircle(const Offset(55, 100), 12, fillPaint);
    canvas.drawCircle(const Offset(55, 100), 12, borderPaint);
    _drawLetter(canvas, const Offset(55, 100), 'M');

    canvas.drawCircle(const Offset(165, 100), 12, fillPaint);
    canvas.drawCircle(const Offset(165, 100), 12, borderPaint);
    _drawLetter(canvas, const Offset(165, 100), 'K');

    // Layer 2
    canvas.drawCircle(const Offset(28, 165), 10, fillPaint);
    canvas.drawCircle(const Offset(28, 165), 10, borderPaint);

    canvas.drawCircle(const Offset(82, 165), 10, fillPaint);
    canvas.drawCircle(const Offset(82, 165), 10, borderPaint);

    canvas.drawCircle(const Offset(138, 165), 10, fillPaint);
    canvas.drawCircle(const Offset(138, 165), 10, borderPaint);

    canvas.drawCircle(const Offset(192, 165), 10, fillPaint);
    canvas.drawCircle(const Offset(192, 165), 10, borderPaint);
  }

  void _drawLetter(Canvas canvas, Offset offset, String letter) {
    const textStyle = TextStyle(
      color: Color(0xFF1A2235),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: letter, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(offset.dx - textPainter.width / 2, offset.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

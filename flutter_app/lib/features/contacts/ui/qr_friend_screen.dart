import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../auth/domain/auth_state.dart';
import '../domain/contacts_notifier.dart';
import '../domain/qr_contact_payload.dart';

/// Camera permission state for the scan tab.
enum _CamPerm { checking, granted, denied, permanentlyDenied }

/// QR-based friend adding: scan someone's code, or show your own.
class QRFriendScreen extends ConsumerStatefulWidget {
  const QRFriendScreen({super.key});

  @override
  ConsumerState<QRFriendScreen> createState() => _QRFriendScreenState();
}

class _QRFriendScreenState extends ConsumerState<QRFriendScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  MobileScannerController? _scanner;

  /// mobile_scanner v7 no longer auto-manages the camera — we drive start/stop
  /// ourselves (per tab + app lifecycle). Tracks whether it's currently on so
  /// we don't double-start (which throws).
  bool _cameraRunning = false;

  _CamPerm _perm = _CamPerm.checking;
  bool _torchOn = false;

  /// Blocks re-entrancy while an add request is in flight.
  bool _processing = false;

  /// The last raw QR text we acted on — dedupes the camera firing the same
  /// code dozens of times per second while it's held in frame.
  String? _recentRaw;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Camera is only alive while the Scan tab is showing — keeps the torch/
    // preview off (and the battery happy) while viewing "My QR".
    _tabs.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera while backgrounded; resume it when we come back (only
    // if the Scan tab is the one showing).
    if (_scanner == null || _perm != _CamPerm.granted) return;
    if (state == AppLifecycleState.resumed) {
      if (_tabs.index == 0) _startCamera();
    } else {
      _stopCamera();
    }
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 0) {
      _startCamera();
    } else {
      _stopCamera();
    }
  }

  Future<void> _startCamera() async {
    final scanner = _scanner;
    if (scanner == null || _cameraRunning) return;
    _cameraRunning = true;
    try {
      await scanner.start();
    } catch (_) {
      _cameraRunning = false;
    }
  }

  Future<void> _stopCamera() async {
    final scanner = _scanner;
    if (scanner == null || !_cameraRunning) return;
    _cameraRunning = false;
    try {
      await scanner.stop();
    } catch (_) {}
  }

  Future<void> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    if (status.isGranted) {
      // v7: create the controller, then start it ourselves.
      _scanner ??= MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      setState(() => _perm = _CamPerm.granted);
      if (_tabs.index == 0) _startCamera();
    } else {
      setState(() => _perm = status.isPermanentlyDenied
          ? _CamPerm.permanentlyDenied
          : _CamPerm.denied);
    }
  }

  // ── Scan handling ──────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    final raw =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || raw == _recentRaw) return;
    _recentRaw = raw;
    _handleRaw(raw);
  }

  Future<void> _handleRaw(String raw) async {
    final payload = QrContactPayload.tryParse(raw);
    if (payload == null) {
      _snack('Invalid QR code — that\'s not a Lumio code.', danger: true);
      _allowRescanLater();
      return;
    }

    // Self-scan?
    final auth = ref.read(authNotifierProvider);
    final me = auth is AuthAuthenticated ? auth.me : null;
    final myEmail = me?.email?.toLowerCase();
    if (payload.userId == me?.id ||
        (myEmail != null && payload.email.toLowerCase() == myEmail)) {
      _snack("That's your own QR code 🙂");
      _allowRescanLater();
      return;
    }

    // Already a contact? (the backend add is idempotent, so we detect it here
    // to give honest feedback instead of a misleading "added".)
    final contacts = ref.read(contactsNotifierProvider).contacts;
    final already = contacts.any((c) =>
        c.id == payload.userId ||
        (c.email?.toLowerCase() == payload.email.toLowerCase()));
    if (already) {
      _snackAndPop("You're already friends with ${payload.name}.");
      return;
    }

    setState(() => _processing = true);
    try {
      await ref
          .read(contactsNotifierProvider.notifier)
          .addContact(email: payload.email);
      _snackAndPop('Friend added!', success: true);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final code = data is Map ? data['code'] as String? : null;
      if (status == 404 || code == 'not_found' || code == 'user_not_found') {
        _snack('User not found — they may have left Lumio.', danger: true);
      } else if (status == 409 || code == 'already_contact') {
        _snackAndPop("You're already friends with ${payload.name}.");
        return;
      } else {
        _snack("Couldn't add — check your connection and try again.",
            danger: true);
      }
      if (mounted) setState(() => _processing = false);
      _allowRescanLater();
    } catch (_) {
      _snack("Couldn't add — check your connection and try again.",
          danger: true);
      if (mounted) setState(() => _processing = false);
      _allowRescanLater();
    }
  }

  /// Clear the dedupe key after a beat so the user can re-present the same
  /// code (e.g. after fixing connectivity) without leaving the screen.
  void _allowRescanLater() {
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _recentRaw = null;
    });
  }

  void _snack(String message, {bool danger = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: danger ? AppColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _snackAndPop(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (context.canPop()) context.pop();
  }

  Future<void> _toggleTorch() async {
    await _scanner?.toggleTorch();
    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text('Add friend', style: AppTextStyles.h1(color: colors.fg1)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: colors.fg2,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Scan QR'),
            Tab(text: 'My QR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildScanTab(colors),
          _MyQrTab(colors: colors),
        ],
      ),
    );
  }

  Widget _buildScanTab(LumioColors colors) {
    switch (_perm) {
      case _CamPerm.checking:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        );
      case _CamPerm.denied:
      case _CamPerm.permanentlyDenied:
        return _CameraPermissionPrompt(
          colors: colors,
          permanentlyDenied: _perm == _CamPerm.permanentlyDenied,
          onAllow: _ensureCameraPermission,
        );
      case _CamPerm.granted:
        return _buildScanner(colors);
    }
  }

  Widget _buildScanner(LumioColors colors) {
    final scanner = _scanner;
    if (scanner == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: scanner, onDetect: _onDetect),
        // Dim the edges so the scan window pops.
        const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x33000000)),
        ),
        // Scan window.
        Center(
          child: Container(
            width: 248,
            height: 248,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        // Instruction + torch.
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Point your camera at a Lumio QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              _CircleIconButton(
                icon: _torchOn
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
                onTap: _toggleTorch,
                tooltip: 'Toggle flash',
              ),
            ],
          ),
        ),
        if (_processing)
          const ColoredBox(
            color: Color(0x66000000),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// ── Camera permission prompt ─────────────────────────────────────────────────

class _CameraPermissionPrompt extends StatelessWidget {
  const _CameraPermissionPrompt({
    required this.colors,
    required this.permanentlyDenied,
    required this.onAllow,
  });

  final LumioColors colors;
  final bool permanentlyDenied;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.photo_camera_rounded,
                size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Camera access needed',
            style: AppTextStyles.h1(color: colors.fg1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            permanentlyDenied
                ? 'Enable camera for Lumio in Settings to scan a friend\'s QR code.'
                : 'Lumio needs your camera to scan a friend\'s QR code.',
            style: AppTextStyles.body(color: colors.fg2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: permanentlyDenied ? openAppSettings : onAllow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              child: Text(
                permanentlyDenied ? 'Open settings' : 'Allow camera',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── My QR tab ────────────────────────────────────────────────────────────────

class _MyQrTab extends ConsumerStatefulWidget {
  const _MyQrTab({required this.colors});

  final LumioColors colors;

  @override
  ConsumerState<_MyQrTab> createState() => _MyQrTabState();
}

class _MyQrTabState extends ConsumerState<_MyQrTab> {
  /// Wraps the branded card so it can be rasterised into a shareable PNG.
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  /// Capture the branded card to a PNG and hand it to the system share sheet.
  Future<void> _shareQr() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card not ready');
      // 3x device pixels → a crisp image that stays scannable when resized.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('PNG encode failed');

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/lumio_qr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: 'Add me on Lumio — scan my QR code to connect.',
          subject: 'My Lumio QR code',
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't share your QR code")),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final auth = ref.watch(authNotifierProvider);
    final me = auth is AuthAuthenticated ? auth.me : null;
    final email = me?.email;

    if (me == null || email == null || email.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Your account has no email to share yet.',
            style: AppTextStyles.body(color: colors.fg2),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final payload = QrContactPayload(
      userId: me.id,
      email: email,
      name: me.name,
    ).encode();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          // Branded QR card — wrapped in a RepaintBoundary so "Share my code"
          // can capture exactly what's on screen.
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, Color(0xFF6D5DF6)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'LUMIO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // White rounded plate keeps the code high-contrast and
                  // scannable regardless of light/dark theme.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 240,
                      gapless: true,
                      backgroundColor: Colors.white,
                      // High EC so the centered logo doesn't break scanning.
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: AppColors.primary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.circle,
                        color: Color(0xFF101828),
                      ),
                      embeddedImage: const AssetImage('assets/lumin-logo.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(
                        size: Size(52, 52),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    me.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Have a friend scan this code to add you on Lumio.',
            style: AppTextStyles.body(color: colors.fg2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _shareQr,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.share_rounded, size: 20),
              label: Text(_sharing ? 'Preparing…' : 'Share my code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.6),
                disabledForegroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 0,
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small reusable circle button (torch) ─────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

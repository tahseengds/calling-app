import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../domain/calls_notifier.dart';

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  String _activeFilter = 'All';
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final calls = ref.watch(callsNotifierProvider);
    final theme = Theme.of(context);
    final lumioColors = context.lumioColors;

    // Filter calls list
    List<CallHistoryItem> filteredList = calls;
    if (_activeFilter == 'Missed') {
      filteredList = calls.where((c) => c.isMissed).toList();
    } else if (_activeFilter == 'Video') {
      filteredList = calls.where((c) => c.callType == 'video').toList();
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Calls',
                      style: AppTextStyles.h1(color: lumioColors.fg1),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(LumioIcons.search, color: lumioColors.fg1),
                          onPressed: () => context.push('/chat/search'),
                          tooltip: 'Search',
                        ),
                        IconButton(
                          icon: Icon(LumioIcons.more, color: lumioColors.fg1),
                          onPressed: () {},
                          tooltip: 'More options',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Filter Chips ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                AppSpacing.space1,
                AppSpacing.space4,
                AppSpacing.space3,
              ),
              child: Row(
                children: ['All', 'Missed', 'Video'].map((item) {
                  final isOn = item == _activeFilter;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.space2),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _activeFilter = item;
                        _expandedId = null; // collapse details on filter change
                      }),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space4,
                        ),
                        decoration: BoxDecoration(
                          color: isOn ? AppColors.primary : Colors.transparent,
                          border: Border.all(
                            color: isOn ? Colors.transparent : lumioColors.hairline,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Center(
                          child: Text(
                            item,
                            style: AppTextStyles.secondaryMedium(
                              color: isOn ? Colors.white : lumioColors.fg1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Call Log List ─────────────────────────────────────────────
            Expanded(
              child: filteredList.isEmpty
                  ? _buildEmptyState(lumioColors)
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final c = filteredList[index];
                        final isOpen = _expandedId == c.id;
                        final isLast = index == filteredList.length - 1;

                        IconData arrowIcon;
                        Color arrowColor;
                        if (c.isMissed) {
                          arrowIcon = LumioIcons.arrowDownLeft;
                          arrowColor = AppColors.danger;
                        } else if (c.direction == 'in') {
                          arrowIcon = LumioIcons.arrowDownLeft;
                          arrowColor = AppColors.success;
                        } else {
                          arrowIcon = LumioIcons.arrowUpRight;
                          arrowColor = lumioColors.fg2;
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            border: Border(
                              left: BorderSide(color: lumioColors.hairline),
                              right: BorderSide(color: lumioColors.hairline),
                              top: index == 0
                                  ? BorderSide(color: lumioColors.hairline)
                                  : BorderSide.none,
                              bottom: BorderSide(color: lumioColors.hairline),
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: index == 0
                                  ? const Radius.circular(AppRadius.xxl)
                                  : Radius.zero,
                              bottom: isLast
                                  ? const Radius.circular(AppRadius.xxl)
                                  : Radius.zero,
                            ),
                          ),
                          child: Column(
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _expandedId = isOpen ? null : c.id;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        // Avatar
                                        UserAvatar(
                                          displayName: c.name,
                                          radius: 24,
                                        ),
                                        const SizedBox(width: 14),
                                        // Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                c.name,
                                                style: AppTextStyles.bodySemibold(
                                                  color: c.isMissed ? AppColors.danger : lumioColors.fg1,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    arrowIcon,
                                                    size: 14,
                                                    color: arrowColor,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    c.callType == 'video' ? LumioIcons.video : LumioIcons.phone,
                                                    size: 12,
                                                    color: lumioColors.fg2,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '${c.callType == 'video' ? 'Video' : 'Voice'} · ${c.duration}',
                                                    style: AppTextStyles.secondary(color: lumioColors.fg2),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Timestamp
                                        Text(
                                          c.time,
                                          style: AppTextStyles.secondary(color: lumioColors.fg2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Expanded Action Row
                              if (isOpen)
                                Container(
                                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                                  color: lumioColors.surfaceLo,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _buildActionButton(
                                          icon: LumioIcons.message,
                                          label: 'Message',
                                          onTap: () => context.push('/chat/${c.id}'),
                                          colors: lumioColors,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _buildActionButton(
                                          icon: LumioIcons.phone,
                                          label: 'Voice',
                                          onTap: () => context.push('/call/outgoing?kind=voice&name=${Uri.encodeComponent(c.name)}'),
                                          colors: lumioColors,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _buildActionButton(
                                          icon: LumioIcons.video,
                                          label: 'Video',
                                          filled: true,
                                          onTap: () => context.push('/call/outgoing?kind=video&name=${Uri.encodeComponent(c.name)}'),
                                          colors: lumioColors,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required LumioColors colors,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.transparent,
          border: Border.all(
            color: filled ? Colors.transparent : colors.hairlineStrong,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: filled
              ? const [
                  BoxShadow(
                    color: Color(0x2E5B7CFA),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: filled ? Colors.white : colors.fg1,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : colors.fg1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(LumioColors lumioColors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(
                    color: Color(0x145B7CFA),
                    shape: BoxShape.circle,
                  ),
                ),
                const Icon(
                  LumioIcons.phone,
                  size: 48,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space6),
            Text(
              'No calls yet',
              style: AppTextStyles.display(color: lumioColors.fg1).copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              "When you call or get a call from family, it'll show up here.",
              style: AppTextStyles.secondary(color: lumioColors.fg2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

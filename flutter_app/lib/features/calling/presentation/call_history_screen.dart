import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../data/call_repository.dart';
import '../../../features/chat/data/conversation_repository.dart';
import '../domain/call_notifier.dart';
import '../domain/call_state.dart';
import 'widgets/permission_denied_screen.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _callHistoryProvider =
    FutureProvider<List<CallRecord>>((ref) async {
  return ref.watch(callRepositoryProvider).getCallHistory();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() =>
      _CallHistoryScreenState();
}

class _CallHistoryScreenState
    extends ConsumerState<CallHistoryScreen> {
  String _filter = 'All'; // 'All' | 'Missed' | 'Video'
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(_callHistoryProvider);
    final lumioColors = context.lumioColors;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── App bar ───────────────────────────────────────────────
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
                    Text('Calls',
                        style: AppTextStyles.h1(color: lumioColors.fg1)),
                    IconButton(
                      icon: Icon(LumioIcons.search,
                          color: lumioColors.fg1),
                      tooltip: 'Search',
                      onPressed: () =>
                          context.push('/chat/search'),
                    ),
                  ],
                ),
              ),
            ),

            // ── Filter chips ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                AppSpacing.space1,
                AppSpacing.space4,
                AppSpacing.space3,
              ),
              child: Row(
                children: ['All', 'Missed', 'Video'].map((item) {
                  final isOn = item == _filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.space2),
                    child: Semantics(
                      button: true,
                      selected: isOn,
                      label: '$item filter',
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _filter = item;
                          _expandedId = null;
                        }),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space4),
                          decoration: BoxDecoration(
                            color: isOn
                                ? AppColors.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: isOn
                                  ? Colors.transparent
                                  : lumioColors.hairline,
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Center(
                            child: Text(
                              item,
                              style: AppTextStyles.secondaryMedium(
                                color: isOn
                                    ? Colors.white
                                    : lumioColors.fg1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── List ──────────────────────────────────────────────────
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) => RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(_callHistoryProvider),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Text(
                            'Could not load calls',
                            style: AppTextStyles.secondary(
                                color: lumioColors.fg2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                data: (records) {
                  final filtered = _applyFilter(records);
                  if (filtered.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(_callHistoryProvider),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: _EmptyState(lumioColors: lumioColors),
                          ),
                        ],
                      ),
                    );
                  }
                  final entries = _groupByDate(filtered);
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(_callHistoryProvider),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding:
                          const EdgeInsets.all(AppSpacing.space4),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        if (e.header != null) {
                          return _DateHeader(
                            label: e.header!,
                            isFirst: index == 0,
                            lumioColors: lumioColors,
                          );
                        }
                        final record = e.record!;
                        return _CallRow(
                          record: record,
                          isFirst: e.isFirstInGroup,
                          isLast: e.isLastInGroup,
                          isOpen: _expandedId == record.id,
                          onTap: () => setState(() {
                            _expandedId = _expandedId == record.id
                                ? null
                                : record.id;
                          }),
                          lumioColors: lumioColors,
                        );
                      },
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

  /// Section label for a call's date — "Today" / "Yesterday" / "This week",
  /// then the month (with year when it's not the current year).
  String _sectionLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final month = months[dt.month - 1];
    return dt.year == now.year ? month : '$month ${dt.year}';
  }

  /// Flatten the (time-descending) records into header + row entries, tagging
  /// each row with its position in its section so the card corners round
  /// correctly per group.
  List<_HistoryItem> _groupByDate(List<CallRecord> records) {
    final items = <_HistoryItem>[];
    var i = 0;
    while (i < records.length) {
      final label = _sectionLabel(records[i].startedAt);
      var j = i;
      while (j < records.length &&
          _sectionLabel(records[j].startedAt) == label) {
        j++;
      }
      items.add(_HistoryItem.header(label));
      for (var k = i; k < j; k++) {
        items.add(_HistoryItem.row(
          records[k],
          isFirstInGroup: k == i,
          isLastInGroup: k == j - 1,
        ));
      }
      i = j;
    }
    return items;
  }

  List<CallRecord> _applyFilter(List<CallRecord> records) {
    return switch (_filter) {
      'Missed' => records.where((r) => r.isMissed).toList(),
      'Video' => records.where((r) => r.callType == CallType.video).toList(),
      _ => records,
    };
  }
}

// ── Date-grouped list entries ───────────────────────────────────────────────

/// Either a section header (when [header] != null) or a call row. [record]'s
/// position flags drive per-group card-corner rounding.
class _HistoryItem {
  final String? header;
  final CallRecord? record;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _HistoryItem.header(this.header)
      : record = null,
        isFirstInGroup = false,
        isLastInGroup = false;

  const _HistoryItem.row(
    this.record, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : header = null;
}

class _DateHeader extends StatelessWidget {
  final String label;
  final bool isFirst;
  final LumioColors lumioColors;

  const _DateHeader({
    required this.label,
    required this.isFirst,
    required this.lumioColors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 20, bottom: 8, left: 4),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.captionSemibold(color: lumioColors.fg3)
            .copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

// ── Row widget ────────────────────────────────────────────────────────────────

class _CallRow extends ConsumerWidget {
  final CallRecord record;
  final bool isFirst;
  final bool isLast;
  final bool isOpen;
  final VoidCallback onTap;
  final LumioColors lumioColors;

  const _CallRow({
    required this.record,
    required this.isFirst,
    required this.isLast,
    required this.isOpen,
    required this.onTap,
    required this.lumioColors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final (IconData arrowIcon, Color arrowColor) = switch (record) {
      CallRecord(isMissed: true) => (
          LumioIcons.arrowDownLeft,
          AppColors.danger
        ),
      CallRecord(direction: CallDirection.incoming) => (
          LumioIcons.arrowDownLeft,
          AppColors.success
        ),
      _ => (LumioIcons.arrowUpRight, lumioColors.fg2),
    };

    final durationLabel = record.durationSeconds != null
        ? _fmt(record.durationSeconds!)
        : (record.isMissed ? 'Missed' : '–');

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(
          left: BorderSide(color: lumioColors.hairline),
          right: BorderSide(color: lumioColors.hairline),
          top: isFirst
              ? BorderSide(color: lumioColors.hairline)
              : BorderSide.none,
          bottom: BorderSide(color: lumioColors.hairline),
        ),
        borderRadius: BorderRadius.vertical(
          top: isFirst
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
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    UserAvatar(
                      displayName: record.peerUser.name,
                      imageUrl: record.peerUser.avatarUrl,
                      radius: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.peerUser.name,
                            style: AppTextStyles.bodySemibold(
                              color: record.isMissed
                                  ? AppColors.danger
                                  : lumioColors.fg1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(arrowIcon,
                                  size: 14, color: arrowColor),
                              const SizedBox(width: 6),
                              Icon(
                                record.callType == CallType.video
                                    ? LumioIcons.video
                                    : LumioIcons.phone,
                                size: 12,
                                color: lumioColors.fg2,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${record.callType == CallType.video ? 'Video' : 'Voice'} · $durationLabel',
                                style: AppTextStyles.secondary(
                                    color: lumioColors.fg2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(record.startedAt),
                      style: AppTextStyles.secondary(
                          color: lumioColors.fg2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Expanded action row — AnimatedSize so the expand/collapse
          // glides instead of snapping.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: isOpen
                ? Container(
                    padding:
                        const EdgeInsets.fromLTRB(18, 4, 18, 16),
                    color: lumioColors.surfaceLo,
                    child: Row(
                      children: [
                        Expanded(
                          child: _ActionBtn(
                            icon: LumioIcons.message,
                            label: 'Message',
                            onTap: () => _openChat(context, ref),
                            lumioColors: lumioColors,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionBtn(
                            icon: LumioIcons.phone,
                            label: 'Voice',
                            onTap: () => _placeCall(
                                context, ref, CallType.audio),
                            lumioColors: lumioColors,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionBtn(
                            icon: LumioIcons.video,
                            label: 'Video',
                            filled: true,
                            onTap: () => _placeCall(
                                context, ref, CallType.video),
                            lumioColors: lumioColors,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    try {
      final convId = await ref
          .read(conversationRepositoryProvider)
          .getOrCreateConversation(record.peerUser.id);
      if (context.mounted) {
        context.push(
            '/chat/$convId?name=${Uri.encodeComponent(record.peerUser.name)}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open conversation')),
        );
      }
    }
  }

  Future<void> _placeCall(
      BuildContext context, WidgetRef ref, CallType callType) async {
    // ── Microphone (required for all calls) ───────────────────────
    var micStatus = await Permission.microphone.status;
    if (micStatus.isPermanentlyDenied) {
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const PermissionDeniedScreen(
              type: PermissionDeniedType.microphone),
        ));
      }
      return;
    }
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return;
    }

    // ── Camera (required for video; downgrade if denied) ──────────
    if (callType == CallType.video) {
      var camStatus = await Permission.camera.status;
      if (camStatus.isPermanentlyDenied) {
        if (context.mounted) {
          await Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const PermissionDeniedScreen(
                type: PermissionDeniedType.camera),
          ));
        }
        return;
      }
      if (!camStatus.isGranted) {
        camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) {
          callType = CallType.audio; // downgrade, don't block
        }
      }
    }

    if (!context.mounted) return;
    ref.read(callSessionProvider.notifier).startCall(
          record.peerUser,
          callType,
        );
    context.push('/call/outgoing');
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _timeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    // Older than a week → show an actual date so it's readable at a glance
    // (e.g. "15 Jan", or "15 Jan 2024" when it's not the current year).
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label = '${dt.day} ${months[dt.month - 1]}';
    return dt.year == now.year ? label : '$label ${dt.year}';
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final LumioColors lumioColors;
  final bool filled;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.lumioColors,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.transparent,
          border: Border.all(
            color:
                filled ? Colors.transparent : lumioColors.hairlineStrong,
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
            Icon(icon,
                size: 16,
                color: filled ? Colors.white : lumioColors.fg1),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : lumioColors.fg1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final LumioColors lumioColors;
  const _EmptyState({required this.lumioColors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: Color(0x145B7CFA),
                shape: BoxShape.circle,
              ),
              child: const Icon(LumioIcons.phone,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.space6),
            Text(
              'No calls yet',
              style: AppTextStyles.display(color: lumioColors.fg1)
                  .copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              "When you call or receive a call, it'll appear here.",
              style: AppTextStyles.secondary(color: lumioColors.fg2),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

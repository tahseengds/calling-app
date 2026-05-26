import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/battery_optimization_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/battery_optimization_sheet.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../../../shared/widgets/permissions_sheet.dart';
import '../../contacts/ui/contacts_screen.dart';
import '../../profile/ui/profile_screen.dart';
import '../../calling/presentation/call_history_screen.dart';
// Polished "Messages" home — rich card list backed by live conversation data.
import '../../chat/presentation/chats_home_screen.dart';

final shellTabProvider = StateProvider<int>((_) => 0);

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runOnboarding());
  }

  Future<void> _runOnboarding() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final permsDone = prefs.getBool('onboarding_perms_done') ?? false;

    if (!permsDone) {
      // Check if any core permission is still not granted.
      final statuses = await Future.wait([
        Permission.microphone.status,
        Permission.camera.status,
        Permission.notification.status,
      ]);
      final anyMissing = statuses.any((s) => !s.isGranted);
      if (anyMissing && mounted) {
        await showPermissionsSheet(context);
      }
      await prefs.setBool('onboarding_perms_done', true);
    }

    // Battery optimization — show once if not exempt.
    if (!mounted) return;
    final svc = ref.read(batteryOptimizationServiceProvider);
    final battDone =
        prefs.getBool('onboarding_battery_done') ?? false;
    if (!battDone) {
      final exempt = await svc.isIgnoringBatteryOptimizations();
      final oem = await svc.getOemHints();
      if ((!exempt || oem.isAggressive) && mounted) {
        await showBatteryOptimizationSheet(context, svc, oem);
      }
      await prefs.setBool('onboarding_battery_done', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(shellTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: const [
          ChatsHomeScreen(),
          CallHistoryScreen(),
          ContactsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _FlBottomNav(
        currentIndex: tabIndex,
        onTap: (i) => ref.read(shellTabProvider.notifier).state = i,
      ),
    );
  }
}

const _navItems = [
  _NavItem(label: 'Messages', icon: LumioIcons.message),
  _NavItem(label: 'Calls', icon: LumioIcons.phone),
  _NavItem(label: 'Contacts', icon: LumioIcons.users),
  _NavItem(label: 'Settings', icon: LumioIcons.settings),
];

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem({required this.label, required this.icon});
}

class _FlBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FlBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final border = isDark ? AppColors.darkHairline : AppColors.lightHairline;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                for (int i = 0; i < _navItems.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: _navItems[i],
                      isActive: i == currentIndex,
                      onTap: () => onTap(i),
                      isDark: isDark,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primary;
    final inactiveColor = isDark ? AppColors.darkFg3 : AppColors.lightFg2;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryPill : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              item.icon,
              color: isActive ? activeColor : inactiveColor,
              size: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_colors.dart';
import '../../contacts/ui/contacts_screen.dart';
import '../../profile/ui/profile_screen.dart';

/// Which bottom-nav tab is currently active.
/// Exposed as a provider so other features (e.g. a call notification) can
/// switch to the Calls tab with a single ref.read().
final shellTabProvider = StateProvider<int>((_) => 2); // default: Family

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(shellTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: const [
          _ComingSoon(label: 'Calls', icon: Icons.call_outlined),
          _ComingSoon(label: 'Messages', icon: Icons.chat_bubble_outline),
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

// ── FamilyLink custom bottom nav ─────────────────────────────────────────────

const _navItems = [
  _NavItem(label: 'Calls', icon: Icons.call_outlined, activeIcon: Icons.call),
  _NavItem(
    label: 'Messages',
    icon: Icons.chat_bubble_outline,
    activeIcon: Icons.chat_bubble,
  ),
  _NavItem(
    label: 'Family',
    icon: Icons.people_outline,
    activeIcon: Icons.people,
  ),
  _NavItem(
    label: 'Profile',
    icon: Icons.person_outline,
    activeIcon: Icons.person,
  ),
];

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class _FlBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _FlBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkHairline : AppColors.lightHairline;

    return Container(
      height: 72 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Active tab gets a pill background
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primaryPill : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive ? activeColor : inactiveColor,
              size: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Placeholder for tabs not built yet ───────────────────────────────────────

class _ComingSoon extends StatelessWidget {
  final String label;
  final IconData icon;

  const _ComingSoon({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 56,
            color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming in the next build',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
            ),
          ),
        ],
      ),
    );
  }
}

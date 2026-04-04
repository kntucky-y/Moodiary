import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/moodiary_colors.dart';
import '../utils/transitions.dart';

const _kPurple = Color(0xFFA076F9);

enum SidebarSection {
  home,
  userProfile,
  calendar,
  journal,
  friends,
  forums,
  resources,
  settings,
}

class AppSidebar extends StatelessWidget {
  final String userName;
  final SidebarSection activeSection;
  final VoidCallback onClose;
  final VoidCallback? onNavigateHome;
  final VoidCallback? onNavigateUserProfile;
  final VoidCallback? onNavigateCalendar;
  final VoidCallback? onNavigateJournal;
  final VoidCallback? onNavigateFriends;
  final VoidCallback? onNavigateForums;
  final VoidCallback? onNavigateSettings;
  final VoidCallback? onChangeCompanion;
  final VoidCallback? onLogout;

  const AppSidebar({
    super.key,
    required this.userName,
    required this.activeSection,
    required this.onClose,
    this.onNavigateHome,
    this.onNavigateUserProfile,
    this.onNavigateCalendar,
    this.onNavigateJournal,
    this.onNavigateFriends,
    this.onNavigateForums,
    this.onNavigateSettings,
    this.onChangeCompanion,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;
    final surface = context.mdSurface;

    final items = [
      _SidebarEntry(
        section: SidebarSection.home,
        icon: Icons.home_rounded,
        label: 'Home',
        onTap: onNavigateHome,
      ),
      _SidebarEntry(
        section: SidebarSection.userProfile,
        icon: Icons.account_circle_outlined,
        label: 'User Profile',
        onTap: onNavigateUserProfile,
      ),
      _SidebarEntry(
        section: SidebarSection.calendar,
        icon: Icons.calendar_month_outlined,
        label: 'Calendar',
        onTap: onNavigateCalendar,
      ),
      _SidebarEntry(
        section: SidebarSection.journal,
        icon: Icons.book_outlined,
        label: 'Journal',
        onTap: onNavigateJournal,
      ),
      _SidebarEntry(
        section: SidebarSection.friends,
        icon: Icons.people_alt_outlined,
        label: 'Buddies',
        onTap: onNavigateFriends,
      ),
      _SidebarEntry(
        section: SidebarSection.forums,
        icon: Icons.chat_bubble_outline,
        label: 'Forums',
        onTap: onNavigateForums,
      ),
      _SidebarEntry(
        section: SidebarSection.resources,
        icon: Icons.folder_outlined,
        label: 'Resources',
        onTap: null,
      ),
      _SidebarEntry(
        section: SidebarSection.settings,
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: onNavigateSettings,
      ),
    ];

    return Material(
      elevation: 16,
      child: SafeArea(
        child: FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, snapshot) {
            final storedName = snapshot.data?.getString('user_name')?.trim();
            final currentName = storedName != null && storedName.isNotEmpty
                ? storedName
                : userName;
            return Container(
              color: surface,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'moodiary',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _kPurple,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: subtleText),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hi, $currentName!',
                    style: TextStyle(color: subtleText, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ...items.map(_buildItem),
                  const SizedBox(height: 12),
                  if (onChangeCompanion != null)
                    TapScale(
                      onTap: onChangeCompanion!,
                      child: const _SidebarItem(
                        icon: Icons.swap_horiz_rounded,
                        label: 'Change Companion',
                      ),
                    ),
                  const Spacer(),
                  if (onLogout != null)
                    TapScale(
                      onTap: onLogout!,
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: subtleText, size: 22),
                          const SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(color: subtleText, fontSize: 16),
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
    );
  }

  Widget _buildItem(_SidebarEntry entry) {
    final active = activeSection == entry.section;
    final item = _SidebarItem(
      icon: entry.icon,
      label: entry.label,
      active: active,
    );
    if (entry.onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: item,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TapScale(onTap: entry.onTap!, child: item),
    );
  }
}

class _SidebarEntry {
  final SidebarSection section;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SidebarEntry({
    required this.section,
    required this.icon,
    required this.label,
    this.onTap,
  });
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;
    final primaryText = context.mdPrimaryText;
    return Row(
      children: [
        Icon(icon, color: active ? _kPurple : subtleText, size: 22),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: active ? _kPurple : primaryText,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/moodiary_colors.dart';
import '../utils/transitions.dart';
import 'glass.dart';

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
  final VoidCallback? onNavigateResources;
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
    this.onNavigateResources,
    this.onNavigateSettings,
    this.onChangeCompanion,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;

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
        onTap: onNavigateResources,
      ),
      _SidebarEntry(
        section: SidebarSection.settings,
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: onNavigateSettings,
      ),
    ];

    return SafeArea(
      child: FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          final storedName = snapshot.data?.getString('user_name')?.trim();
          final currentName = storedName != null && storedName.isNotEmpty
              ? storedName
              : userName;
          return GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.zero,
            backgroundColor: context.mdGlassSurfaceStrong,
            borderColor: Colors.transparent,
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
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ...items.map(_buildItem),
                      if (onChangeCompanion != null)
                        _buildActionItem(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Change Companion',
                          onTap: onChangeCompanion!,
                        ),
                    ],
                  ),
                ),
                if (onLogout != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TapScale(
                      onTap: () => _handleTap(onLogout!),
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
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildItem(_SidebarEntry entry) {
    final active = activeSection == entry.section;
    final item = _SidebarItem(
      icon: entry.icon,
      label: entry.label,
      active: active,
      emphasized: false,
    );
    if (entry.onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: item,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapScale(onTap: () => _handleTap(entry.onTap!), child: item),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapScale(
        onTap: () => _handleTap(onTap),
        child: _SidebarItem(icon: icon, label: label, emphasized: false),
      ),
    );
  }

  void _handleTap(VoidCallback action) {
    onClose();
    action();
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
  final bool emphasized;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;
    final primaryText = context.mdPrimaryText;
    final iconColor = active ? _kPurple : subtleText;
    final textColor = active ? _kPurple : primaryText;
    final row = Row(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              color: textColor,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    if (!active) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: row,
      );
    }

    return GlassContainer(
      blurSigma: context.mdGlassBlurSmall,
      borderRadius: BorderRadius.circular(14),
      backgroundColor: context.mdGlassSurfaceStrong,
      borderColor: _kPurple.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: row,
    );
  }
}

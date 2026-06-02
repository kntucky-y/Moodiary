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

class AppSidebar extends StatefulWidget {
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
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  String? _storedName;

  @override
  void initState() {
    super.initState();
    _loadStoredName();
  }

  Future<void> _loadStoredName() async {
    final prefs = await SharedPreferences.getInstance();
    final nextName = prefs.getString('user_name')?.trim();
    if (!mounted || nextName == _storedName) {
      return;
    }
    setState(() => _storedName = nextName);
  }

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;
    final storedName = _storedName;
    final currentName = storedName != null && storedName.isNotEmpty
        ? storedName
        : widget.userName;

    final items = [
      _SidebarEntry(
        section: SidebarSection.home,
        icon: Icons.home_rounded,
        label: 'Home',
        onTap: widget.onNavigateHome,
      ),
      _SidebarEntry(
        section: SidebarSection.userProfile,
        icon: Icons.account_circle_outlined,
        label: 'User Profile',
        onTap: widget.onNavigateUserProfile,
      ),
      _SidebarEntry(
        section: SidebarSection.friends,
        icon: Icons.people_alt_outlined,
        label: 'Buddies',
        onTap: widget.onNavigateFriends,
      ),
      _SidebarEntry(
        section: SidebarSection.forums,
        icon: Icons.chat_bubble_outline,
        label: 'Forums',
        onTap: widget.onNavigateForums,
      ),
      _SidebarEntry(
        section: SidebarSection.resources,
        icon: Icons.folder_outlined,
        label: 'Resources',
        onTap: widget.onNavigateResources,
      ),
      _SidebarEntry(
        section: SidebarSection.settings,
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: widget.onNavigateSettings,
      ),
    ];

    final topPadding = MediaQuery.of(context).padding.top;
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.zero,
      backgroundColor: context.mdGlassSurfaceStrong,
      borderColor: Colors.transparent,
      padding: EdgeInsets.fromLTRB(24, topPadding + 24, 24, 24),
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
                onPressed: widget.onClose,
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
                if (widget.onChangeCompanion != null)
                  _buildActionItem(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Change Companion',
                    onTap: widget.onChangeCompanion!,
                  ),
                if (widget.onLogout != null)
                  _buildActionItem(
                    icon: Icons.logout,
                    label: 'Logout',
                    onTap: () => _confirmAndLogout(context),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(_SidebarEntry entry) {
    final active = widget.activeSection == entry.section;
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
    widget.onClose();
    action();
  }

  Future<void> _confirmAndLogout(BuildContext context) async {
    if (widget.onLogout == null) return;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text(
            'Are you sure you want to log out? You can sign in again anytime.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );
    if (shouldLogout == true) {
      _handleTap(widget.onLogout!);
    }
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

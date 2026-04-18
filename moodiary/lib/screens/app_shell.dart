import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/moodiary_colors.dart';
import '../widgets/glass.dart';
import 'friends/friends_screen.dart';
import 'forums/forums_screen.dart';
import 'home/home_screen.dart';
import 'profile/user_profile_screen.dart';
import 'resources/resources_screen.dart';

enum MoodiaryTab { profile, buddies, home, forums, resources }

class MoodiaryShell extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  final String? initialProfileAvatarUrl;
  final MoodiaryTab initialTab;

  const MoodiaryShell({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
    this.initialProfileAvatarUrl,
    this.initialTab = MoodiaryTab.home,
  });

  @override
  State<MoodiaryShell> createState() => _MoodiaryShellState();
}

class _MoodiaryShellState extends State<MoodiaryShell> {
  late int _index;
  late final List<Widget> _pages;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab.index;
    _avatarUrl = widget.initialProfileAvatarUrl;
    _pages = [
      const UserProfileScreen(),
      FriendsScreen(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
      ),
      HomeScreen(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
        initialProfileAvatarUrl: widget.initialProfileAvatarUrl,
        showBottomNav: false,
      ),
      ForumsScreen(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
      ),
      const ResourcesScreen(),
    ];
    _loadAvatarUrl();
  }

  Future<void> _loadAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('user_avatar_url');
    if (!mounted || stored == _avatarUrl) return;
    setState(() {
      _avatarUrl = stored;
      _pages[2] = HomeScreen(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
        initialProfileAvatarUrl: stored,
        showBottomNav: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final horizontalInset = media.size.width >= 700 ? 20.0 : 16.0;
    final bottomInset = media.padding.bottom > 0 ? 4.0 : 8.0;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          horizontalInset,
          0,
          horizontalInset,
          bottomInset,
        ),
        child: GlassContainer(
          blurSigma: context.mdGlassBlurSmall,
          borderRadius: BorderRadius.circular(context.mdRadiusLg),
          backgroundColor: context.mdGlassSurfaceStrong,
          padding: EdgeInsets.zero,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            height: 58,
            backgroundColor: Colors.transparent,
            indicatorColor: cs.primaryContainer.withValues(alpha: 0.56),
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.account_circle_outlined),
                selectedIcon: Icon(Icons.account_circle),
                label: 'Profile',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_alt_outlined),
                selectedIcon: Icon(Icons.people_alt),
                label: 'Buddies',
              ),
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Forums',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'Resources',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

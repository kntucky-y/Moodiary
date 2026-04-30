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

typedef ShellTabSelector = void Function(MoodiaryTab tab, {bool fromSidebar});
typedef ShellNavVisibilitySetter = void Function(bool hidden);

class MoodiaryShell extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  final String? initialProfileAvatarUrl;
  final MoodiaryTab initialTab;
  final bool initialHideTopNav;

  const MoodiaryShell({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
    this.initialProfileAvatarUrl,
    this.initialTab = MoodiaryTab.home,
    this.initialHideTopNav = false,
  });

  @override
  State<MoodiaryShell> createState() => _MoodiaryShellState();
}

class _MoodiaryShellState extends State<MoodiaryShell> {
  late int _index;
  late final List<Widget?> _pages;
  String? _avatarUrl;
  final ValueNotifier<bool> _hideBottomNav = ValueNotifier<bool>(false);
  final List<bool?> _tabHideTopNav = List<bool?>.filled(
    MoodiaryTab.values.length,
    null,
  );

  void _setShellNavHidden(bool hidden) {
    if (_hideBottomNav.value == hidden) return;
    _hideBottomNav.value = hidden;
  }

  Widget _buildPage(int index, {required bool hideTopNav}) {
    switch (MoodiaryTab.values[index]) {
      case MoodiaryTab.profile:
        return UserProfileScreen(
          onShellTabSelected: _selectTab,
          showTopNav: !hideTopNav,
          onShellNavVisibilityChanged: _setShellNavHidden,
        );
      case MoodiaryTab.buddies:
        return FriendsScreen(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          onShellTabSelected: _selectTab,
          showTopNav: !hideTopNav,
          onShellNavVisibilityChanged: _setShellNavHidden,
        );
      case MoodiaryTab.home:
        return HomeScreen(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          initialProfileAvatarUrl: _avatarUrl,
          showBottomNav: false,
          onShellTabSelected: _selectTab,
        );
      case MoodiaryTab.forums:
        return ForumsScreen(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          onShellTabSelected: _selectTab,
          showTopNav: !hideTopNav,
          onShellNavVisibilityChanged: _setShellNavHidden,
        );
      case MoodiaryTab.resources:
        return ResourcesScreen(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          onShellTabSelected: _selectTab,
          showTopNav: !hideTopNav,
          onShellNavVisibilityChanged: _setShellNavHidden,
        );
    }
  }

  void _ensurePage(int index, {bool? hideTopNavOverride}) {
    final hideTopNav = hideTopNavOverride ?? _tabHideTopNav[index] ?? false;
    _tabHideTopNav[index] = hideTopNav;
    _pages[index] ??= _buildPage(index, hideTopNav: hideTopNav);
  }

  void _selectTab(MoodiaryTab tab, {bool fromSidebar = false}) {
    final nextIndex = tab.index;
    final hideTopNav = false;
    if (_index == nextIndex) {
      return;
    }
    if (_tabHideTopNav[nextIndex] != hideTopNav) {
      _pages[nextIndex] = null;
    }
    setState(() {
      _ensurePage(nextIndex, hideTopNavOverride: hideTopNav);
      _index = nextIndex;
    });
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab.index;
    _avatarUrl = widget.initialProfileAvatarUrl;
    _pages = List<Widget?>.filled(MoodiaryTab.values.length, null);
    _tabHideTopNav[_index] = false;
    _ensurePage(_index, hideTopNavOverride: false);
    _loadAvatarUrl();
  }

  @override
  void dispose() {
    _hideBottomNav.dispose();
    super.dispose();
  }

  Future<void> _loadAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('user_avatar_url');
    if (!mounted || stored == _avatarUrl) return;
    setState(() {
      _avatarUrl = stored;
      // Note: HomeScreen loads its own avatar from SharedPreferences,
      // so we don't recreate the page here to avoid losing state
      // (mood score, tasks, etc.).
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final horizontalInset = media.size.width >= 1000
        ? 32.0
        : media.size.width >= 700
        ? 24.0
        : 22.0;
    final bottomInset = media.padding.bottom > 0 ? 4.0 : 8.0;
    final navInnerHorizontalInset = media.size.width >= 1000
        ? 180.0
        : media.size.width >= 800
        ? 120.0
        : media.size.width >= 600
        ? 72.0
        : 28.0;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: List<Widget>.generate(
          MoodiaryTab.values.length,
          (index) => _pages[index] ?? const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _hideBottomNav,
        builder: (context, hidden, child) {
          if (hidden) return const SizedBox.shrink();
          return SafeArea(
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
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: navInnerHorizontalInset,
                ),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      _selectTab(MoodiaryTab.values[index]),
                  height: 58,
                  backgroundColor: Colors.transparent,
                  indicatorColor: cs.primaryContainer.withValues(alpha: 0.56),
                  elevation: 0,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
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
        },
      ),
    );
  }
}

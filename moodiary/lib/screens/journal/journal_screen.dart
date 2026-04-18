import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../calendar/calendar_screen.dart';
import '../app_shell.dart';
import '../companion/companion_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
import '../../services/local_notifications_service.dart';
import '../../services/auth_service.dart';
import '../../services/realtime_notifications.dart';
import '../../services/theme_controller.dart';
import '../../utils/transitions.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/glass.dart';
import '../../theme/moodiary_colors.dart';

const _kPurple = Color(0xFFA076F9);
const _kSubtle = Color(0xFF8A8A8D);
const _kBaseUrl = kBackendBaseUrl;

// ─── Tag data ─────────────────────────────────────────────────────────────────
const _kTags = ['terrible', 'bad', 'okay', 'good', 'excellent'];
const _kTagAssets = {
  'terrible': 'assets/terrible.png',
  'bad': 'assets/bad.png',
  'okay': 'assets/okay.png',
  'good': 'assets/good.png',
  'excellent': 'assets/excellent.png',
};

// ─── Model ────────────────────────────────────────────────────────────────────
class _JournalEntry {
  final String id;
  final String title;
  final String content;
  final String tag;
  final DateTime createdAt;
  final bool isArchived;

  const _JournalEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.tag,
    required this.createdAt,
    required this.isArchived,
  });

  factory _JournalEntry.fromJson(Map<String, dynamic> j) => _JournalEntry(
    id: j['_id'] as String,
    title: j['title'] as String,
    content: j['content'] as String,
    tag: (j['tag'] as String?) ?? 'okay',
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    isArchived: (j['isArchived'] as bool?) ?? false,
  );
}

// ─── JournalScreen ────────────────────────────────────────────────────────────
class JournalScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;

  const JournalScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<_JournalEntry> _activeEntries = [];
  List<_JournalEntry> _archivedEntries = [];
  bool _loading = true;
  String? _token;
  bool _sidebarOpen = false;
  bool _fabExpanded = false;
  bool _showArchived = false;
  final Set<String> _workingIds = <String>{};
  bool _activeLoaded = false;
  bool _archivedLoaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    await _fetchEntries(archived: false, force: true);
  }

  Future<void> _fetchEntries({
    required bool archived,
    bool force = false,
  }) async {
    if (_token == null) {
      setState(() => _loading = false);
      return;
    }
    if (!force) {
      final loaded = archived ? _archivedLoaded : _activeLoaded;
      if (loaded) return;
    }

    try {
      if (mounted) {
        final currentList = archived ? _archivedEntries : _activeEntries;
        if (currentList.isEmpty) setState(() => _loading = true);
      }
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/api/journal?archived=$archived'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        final parsed = data
            .map((d) => _JournalEntry.fromJson(d as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            if (archived) {
              _archivedEntries = parsed;
              _archivedLoaded = true;
            } else {
              _activeEntries = parsed;
              _activeLoaded = true;
            }
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleArchived() async {
    final nextShowArchived = !_showArchived;
    setState(() {
      _showArchived = nextShowArchived;
      _fabExpanded = false;
    });
    await _fetchEntries(archived: nextShowArchived);
  }

  void _openSidebar() {
    setState(() {
      _sidebarOpen = true;
      _fabExpanded = false;
    });
  }

  void _closeSidebar() => setState(() => _sidebarOpen = false);

  void _openScreen(Widget page) {
    _closeSidebar();
    Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  void _openShellTab(MoodiaryTab tab) {
    _closeSidebar();
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          initialTab: tab,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _logout() async {
    _closeSidebar();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_name');
    await prefs.remove('user_id');
    await prefs.remove('companion_id');
    await prefs.remove('companion_name');
    RealtimeNotifications.instance.disconnect();
    await ThemeController.instance.resetToDefault();
    await LocalNotificationsService.instance.cancelAllScheduled();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(page: const OnboardingScreen()),
      (_) => false,
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
    Color confirmColor = _kPurple,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _archiveEntry(_JournalEntry entry) async {
    if (_token == null) return;
    final shouldArchive = await _confirmAction(
      title: 'Archive journal?',
      message: 'This will move it to Archive and you can recover it later.',
      confirmText: 'Archive',
    );
    if (!shouldArchive) return;

    setState(() => _workingIds.add(entry.id));
    try {
      final resp = await http.delete(
        Uri.parse('$_kBaseUrl/api/journal/${entry.id}'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final payload = jsonDecode(resp.body) as Map<String, dynamic>;
        final archivedJson = payload['entry'];
        setState(() {
          _activeEntries.removeWhere((e) => e.id == entry.id);
          if (archivedJson is Map<String, dynamic>) {
            final archivedEntry = _JournalEntry.fromJson(archivedJson);
            _archivedEntries.removeWhere((e) => e.id == archivedEntry.id);
            _archivedEntries.insert(0, archivedEntry);
            _archivedLoaded = true;
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Journal archived.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Archive failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _workingIds.remove(entry.id));
    }
  }

  Future<void> _recoverEntry(_JournalEntry entry) async {
    if (_token == null) return;
    setState(() => _workingIds.add(entry.id));
    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/journal/${entry.id}/recover'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final payload = jsonDecode(resp.body) as Map<String, dynamic>;
        final recoveredJson = payload['entry'];
        setState(() {
          _archivedEntries.removeWhere((e) => e.id == entry.id);
          if (recoveredJson is Map<String, dynamic>) {
            final recoveredEntry = _JournalEntry.fromJson(recoveredJson);
            _activeEntries.removeWhere((e) => e.id == recoveredEntry.id);
            _activeEntries.insert(0, recoveredEntry);
            _activeLoaded = true;
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Journal recovered.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to recover: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Recover failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _workingIds.remove(entry.id));
    }
  }

  Future<void> _hardDeleteEntry(_JournalEntry entry) async {
    if (_token == null) return;
    final shouldDelete = await _confirmAction(
      title: 'Delete permanently?',
      message:
          'This will permanently delete this archived journal and cannot be undone.',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );
    if (!shouldDelete) return;

    setState(() => _workingIds.add(entry.id));
    try {
      final resp = await http.delete(
        Uri.parse('$_kBaseUrl/api/journal/${entry.id}/permanent'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _archivedEntries.removeWhere((e) => e.id == entry.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Journal permanently deleted.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete permanently: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _workingIds.remove(entry.id));
    }
  }

  void _openEditor({_JournalEntry? existing}) async {
    setState(() => _fabExpanded = false);
    final result = await Navigator.of(context).push<bool>(
      FadeSlideRoute(
        page: _JournalEditorScreen(
          token: _token,
          companionId: widget.companionId,
          existing: existing,
        ),
      ),
    );
    if (result == true) {
      await _fetchEntries(archived: false, force: true);
      if (_showArchived) {
        await _fetchEntries(archived: true, force: true);
      }
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year.toString().substring(2);
    return '$day $month, $year';
  }

  String _formatWeekday(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[dt.weekday - 1];
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final shownEntries = _showArchived ? _archivedEntries : _activeEntries;
    final primaryText = context.mdPrimaryText;
    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: Stack(
        children: [
          Column(
            children: [
              // ── Header ──────────────────────────────────────────────────────
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _openSidebar,
                            child: Icon(
                              Icons.menu,
                              size: 26,
                              color: primaryText,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _todayStr(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: primaryText,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: _showArchived
                                ? 'Show active journals'
                                : 'Show archived journals',
                            onPressed: _toggleArchived,
                            icon: Icon(
                              _showArchived
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined,
                              size: 22,
                              color: _showArchived ? _kPurple : primaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // "Journa/" title — Playfair "J" + Lexend "ourna" + Caveat "l"
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'J',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                            ),
                            TextSpan(
                              text: 'ourna',
                              style: GoogleFonts.lexend(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                            ),
                            TextSpan(
                              text: 'l',
                              style: GoogleFonts.caveat(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: _kPurple,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _showArchived ? 'Archived journals' : 'Write anything!',
                        style: const TextStyle(color: _kSubtle, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // ── Entry list ──────────────────────────────────────────────────
              Expanded(
                child: GlassContainer(
                  blurSigma: context.mdGlassBlurMedium,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(context.mdRadiusXl),
                  ),
                  backgroundColor: context.mdGlassSurface,
                  borderColor: context.mdGlassBorder,
                  padding: EdgeInsets.zero,
                  child: _loading
                      ? shownEntries.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : _buildEntriesList(shownEntries)
                      : shownEntries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/doodle${widget.companionId}.png',
                                width: 72,
                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox(),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _showArchived
                                    ? 'Archive is empty.'
                                    : 'No entries yet.',
                                style: const TextStyle(
                                  color: _kSubtle,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _showArchived
                                    ? 'Soft-deleted journals appear here.'
                                    : 'Tap + to write your first one!',
                                style: const TextStyle(
                                  color: _kSubtle,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildEntriesList(shownEntries),
                ),
              ),
            ],
          ),
          if (_sidebarOpen)
            GestureDetector(
              onTap: _closeSidebar,
              child: Container(color: context.mdOverlayBarrier),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: _sidebarOpen ? 0 : -280,
            top: 0,
            bottom: 0,
            width: 260,
            child: AppSidebar(
              userName: widget.userName,
              activeSection: SidebarSection.journal,
              onClose: _closeSidebar,
              onNavigateHome: () => _openShellTab(MoodiaryTab.home),
              onNavigateUserProfile: () => _openShellTab(MoodiaryTab.profile),
              onNavigateCalendar: () => _openScreen(
                CalendarScreen(
                  userName: widget.userName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateJournal: _closeSidebar,
              onNavigateFriends: () => _openShellTab(MoodiaryTab.buddies),
              onNavigateForums: () => _openShellTab(MoodiaryTab.forums),
              onNavigateResources: () => _openShellTab(MoodiaryTab.resources),
              onNavigateSettings: () =>
                  _openScreen(SettingsScreen(userName: widget.userName)),
              onChangeCompanion: () =>
                  _openScreen(CompanionScreen(userName: widget.userName)),
              onLogout: () => _logout(),
            ),
          ),
          // ── FAB / companion bubble ───────────────────────────────────────────
          if (!_showArchived && _fabExpanded && !_sidebarOpen)
            GestureDetector(
              onTap: () => setState(() => _fabExpanded = false),
              child: Container(color: Colors.transparent),
            ),
          if (!_showArchived && !_sidebarOpen)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              bottom: 24,
              right: 20,
              child: _fabExpanded
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Image.asset(
                          'assets/doodle${widget.companionId}.png',
                          width: 72,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Speech bubble
                            GlassContainer(
                              blurSigma: context.mdGlassBlurMedium,
                              borderRadius: BorderRadius.circular(12),
                              backgroundColor: context.mdGlassSurfaceStrong,
                              borderColor: context.mdGlassBorder,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                "What's on your mind today?",
                                style: TextStyle(
                                  color: context.mdPrimaryText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // Dismiss
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _fabExpanded = false),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Add
                                GestureDetector(
                                  onTap: () => _openEditor(),
                                  child: SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: GlassContainer(
                                      blurSigma: context.mdGlassBlurMedium,
                                      borderRadius: BorderRadius.circular(26),
                                      backgroundColor:
                                          context.mdGlassSurfaceStrong,
                                      borderColor: context.mdGlassBorder,
                                      padding: EdgeInsets.zero,
                                      child: Icon(
                                        Icons.add,
                                        color: context.mdPrimaryText,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => setState(() => _fabExpanded = true),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: GlassContainer(
                          blurSigma: context.mdGlassBlurMedium,
                          borderRadius: BorderRadius.circular(30),
                          backgroundColor: _kPurple.withValues(alpha: 0.60),
                          borderColor: context.mdGlassBorder,
                          padding: EdgeInsets.zero,
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntriesList(List<_JournalEntry> entries) {
    final primaryText = context.mdPrimaryText;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: entries.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _showArchived ? 'Archived Entries' : 'All Entries',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: primaryText,
              ),
            ),
          );
        }
        final entry = entries[i - 1];
        return _EntryCard(
          entry: entry,
          formatDate: _formatDate,
          formatWeekday: _formatWeekday,
          formatTime: _formatTime,
          onTap: _showArchived ? null : () => _openEditor(existing: entry),
          onArchive: _showArchived ? null : () => _archiveEntry(entry),
          showArchivedActions: _showArchived,
          actionBusy: _workingIds.contains(entry.id),
          onRecover: () => _recoverEntry(entry),
          onPermanentDelete: () => _hardDeleteEntry(entry),
        );
      },
    );
  }
}

// ─── Entry card ───────────────────────────────────────────────────────────────
class _EntryCard extends StatelessWidget {
  final _JournalEntry entry;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatWeekday;
  final String Function(DateTime) formatTime;
  final VoidCallback? onTap;
  final VoidCallback? onArchive;
  final bool showArchivedActions;
  final bool actionBusy;
  final VoidCallback? onRecover;
  final VoidCallback? onPermanentDelete;

  const _EntryCard({
    required this.entry,
    required this.formatDate,
    required this.formatWeekday,
    required this.formatTime,
    required this.onTap,
    this.onArchive,
    this.showArchivedActions = false,
    this.actionBusy = false,
    this.onRecover,
    this.onPermanentDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final asset = _kTagAssets[entry.tag] ?? 'assets/okay.png';
    final preview = entry.content.length > 120
        ? '${entry.content.substring(0, 120)}...'
        : entry.content;

    return TapScale(
      onTap: onTap,
      child: GlassContainer(
        blurSigma: context.mdGlassBlurMedium,
        borderRadius: BorderRadius.circular(20),
        backgroundColor: context.mdGlassSurface,
        borderColor: context.mdGlassBorder,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date column
            Container(
              width: 78,
              padding: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: context.mdInputBorder, width: 1.5),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    formatDate(entry.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatWeekday(entry.createdAt),
                    style: const TextStyle(fontSize: 10, color: _kSubtle),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatTime(entry.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFAAAAAA),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Image.asset(
                    asset,
                    width: 36,
                    height: 36,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.sentiment_neutral, size: 36),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Content column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: primaryText,
                          ),
                        ),
                      ),
                      if (!showArchivedActions && onArchive != null)
                        IconButton(
                          onPressed: onArchive,
                          splashRadius: 18,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.mdSecondaryText,
                      height: 1.5,
                    ),
                  ),
                  if (showArchivedActions) ...[
                    const SizedBox(height: 10),
                    actionBusy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: onRecover,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kPurple,
                                  side: const BorderSide(color: _kPurple),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                icon: const Icon(Icons.restore, size: 16),
                                label: const Text('Recover'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: onPermanentDelete,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                icon: const Icon(Icons.delete, size: 16),
                                label: const Text('Delete'),
                              ),
                            ],
                          ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Journal Editor Screen ────────────────────────────────────────────────────
class _JournalEditorScreen extends StatefulWidget {
  final String? token;
  final int companionId;
  final _JournalEntry? existing;

  const _JournalEditorScreen({
    required this.token,
    required this.companionId,
    this.existing,
  });

  @override
  State<_JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<_JournalEditorScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  String _selectedTag = 'okay';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _bodyCtrl = TextEditingController(text: widget.existing?.content ?? '');
    _selectedTag = widget.existing?.tag ?? 'okay';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _bodyCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both title and content.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final body = jsonEncode({
        'title': title,
        'content': content,
        'tag': _selectedTag,
      });
      final headers = {
        'Content-Type': 'application/json',
        if (widget.token != null) 'Authorization': 'Bearer ${widget.token}',
      };
      http.Response resp;
      if (widget.existing != null) {
        resp = await http.put(
          Uri.parse('$_kBaseUrl/api/journal/${widget.existing!.id}'),
          headers: headers,
          body: body,
        );
      } else {
        resp = await http.post(
          Uri.parse('$_kBaseUrl/api/journal'),
          headers: headers,
          body: body,
        );
      }
      if (mounted) {
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save: ${resp.body}')),
          );
          setState(() => _saving = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 24,
                      color: primaryText,
                    ),
                  ),
                  const Spacer(),
                  _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : GestureDetector(
                          onTap: _save,
                          child: GlassContainer(
                            blurSigma: context.mdGlassBlurMedium,
                            borderRadius: BorderRadius.circular(20),
                            backgroundColor: context.mdGlassSurface,
                            borderColor: context.mdGlassBorder,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: _kPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            ),
            // ── Title + Body ─────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Title...',
                        hintStyle: TextStyle(
                          color: secondaryText,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _bodyCtrl,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(
                          fontSize: 14,
                          color: primaryText,
                          height: 1.6,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Start typing...',
                          hintStyle: TextStyle(
                            color: secondaryText,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Tag picker ───────────────────────────────────────────────────
            _TagPicker(
              selected: _selectedTag,
              onSelect: (tag) => setState(() => _selectedTag = tag),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
          ],
        ),
      ),
    );
  }
}

// ─── Tag picker ───────────────────────────────────────────────────────────────
class _TagPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _TagPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Text(
            'Choose a tag!',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ..._kTags.map((tag) {
                final isSelected = tag == selected;
                return GestureDetector(
                  onTap: () => onSelect(tag),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? _kPurple : Colors.transparent,
                        width: 2.5,
                      ),
                      color: isSelected
                          ? const Color(0xFFF3E8FF)
                          : Colors.transparent,
                    ),
                    child: Image.asset(
                      _kTagAssets[tag]!,
                      width: 40,
                      height: 40,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.sentiment_neutral, size: 40),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

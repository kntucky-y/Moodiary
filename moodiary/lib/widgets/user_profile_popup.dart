import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../utils/avatar_utils.dart';

Future<String?> showUserProfilePopup(
  BuildContext context, {
  required String userId,
}) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _UserProfilePopup(userId: userId),
  );
}

class _UserProfilePopup extends StatelessWidget {
  final String userId;

  const _UserProfilePopup({required this.userId});

  String _formatDate(DateTime dateTime) {
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
    return '${dateTime.day.toString().padLeft(2, '0')} ${months[dateTime.month - 1]} ${dateTime.year}';
  }

  String _excerpt(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 110) return compact;
    return '${compact.substring(0, 107)}...';
  }

  Future<void> _reportUser(BuildContext context, String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    final selfUserId =
        prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
    final token = prefs.getString('token') ?? '';
    if (selfUserId.isEmpty || token.isEmpty || selfUserId == userId) {
      return;
    }

    if (!context.mounted) return;
    final report = await showModalBottomSheet<_ReportDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _ReportUserSheet(userName: displayName),
    );

    if (!context.mounted || report == null) return;

    try {
      await AuthService.instance.reportUser(
        authToken: token,
        targetUserId: userId,
        reason: report.reason,
        details: report.details,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report submitted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not submit report: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 700),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: FutureBuilder<Map<String, dynamic>>(
            future: AuthService.instance.getUserProfile(userId: userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primaryContainer,
                        colorScheme.surface,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: colorScheme.surface,
                        child: Icon(
                          Icons.person_off_outlined,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Unable to load profile',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please try again in a moment.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }

              final payload = snapshot.data ?? const {};
              final user = payload['user'] as Map<String, dynamic>? ?? const {};
              final currentMood =
                  payload['currentMood'] as Map<String, dynamic>?;
              final currentStreak =
                  (payload['currentStreak'] as num?)?.toInt() ?? 0;
              final mbtiLatestType = user['mbtiLatestType'] as String?;
              final publicPosts =
                  (payload['publicPosts'] as List<dynamic>? ?? const [])
                      .cast<Map<String, dynamic>>();

              final name = (user['name'] as String?) ?? 'User';
              final email = (user['email'] as String?) ?? '';
              final bio = (user['bio'] as String?) ?? '';
              final avatarUrl = user['avatarUrl'] as String?;
              final createdAtRaw = user['createdAt'] as String?;
              final joinedDate = createdAtRaw != null
                  ? _formatDate(DateTime.parse(createdAtRaw).toLocal())
                  : 'Unknown';

              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.surface,
                      colorScheme.surfaceContainerHighest,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -40,
                      top: -30,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: -28,
                      bottom: 80,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: colorScheme.tertiary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 34,
                                  backgroundImage: avatarImageProvider(
                                    avatarUrl,
                                  ),
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  child: avatarImageProvider(avatarUrl) == null
                                      ? const Icon(Icons.person, size: 30)
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                            ),
                                          ),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            style: IconButton.styleFrom(
                                              overlayColor: Colors.transparent,
                                              splashFactory:
                                                  NoSplash.splashFactory,
                                            ),
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (email.isNotEmpty)
                                        Text(
                                          email,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.wb_sunny_outlined,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Current Mood',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (currentMood != null)
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: colorScheme
                                              .surfaceContainerHighest,
                                          child: Image.asset(
                                            (currentMood['asset'] as String?) ??
                                                'assets/okay.png',
                                            width: 24,
                                            height: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            (currentMood['label'] as String?) ??
                                                'Okay',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      'No mood logged yet',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_outlined,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Member since $joinedDate',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.local_fire_department_outlined,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        currentStreak > 0
                                            ? '$currentStreak day streak'
                                            : 'No active streak',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.psychology_outlined,
                                        size: 16,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        mbtiLatestType == null ||
                                                mbtiLatestType.isEmpty
                                            ? 'MBTI: Not tested yet'
                                            : 'MBTI: $mbtiLatestType',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bio',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    bio.isNotEmpty ? bio : 'No bio yet',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Public Posts',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (publicPosts.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  'No public posts yet.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            else
                              ...publicPosts.map(
                                (post) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Material(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () {
                                        Navigator.of(
                                          context,
                                        ).pop(post['id'] as String);
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor:
                                                  colorScheme.primaryContainer,
                                              child: Icon(
                                                (post['isAnonymous']
                                                            as bool?) ==
                                                        true
                                                    ? Icons
                                                          .visibility_off_outlined
                                                    : Icons.article_outlined,
                                                size: 18,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (post['title']
                                                            as String?) ??
                                                        'Untitled Post',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _excerpt(
                                                      (post['content']
                                                              as String?) ??
                                                          '',
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .touch_app_outlined,
                                                        size: 14,
                                                        color:
                                                            colorScheme.primary,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Open in Forums',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelSmall
                                                            ?.copyWith(
                                                              color: colorScheme
                                                                  .primary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _MuteToggleButton(targetUserId: userId),
                                const SizedBox(width: 8),
                                _BlockToggleButton(targetUserId: userId),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _reportUser(context, name),
                                icon: const Icon(Icons.flag_outlined),
                                label: const Text('Report user'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  side: BorderSide(color: colorScheme.error),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
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
        ),
      ),
    );
  }
}

class _ReportDraft {
  final String reason;
  final String details;

  const _ReportDraft({required this.reason, required this.details});
}

class _MuteToggleButton extends StatefulWidget {
  final String targetUserId;

  const _MuteToggleButton({required this.targetUserId});

  @override
  State<_MuteToggleButton> createState() => _MuteToggleButtonState();
}

class _MuteToggleButtonState extends State<_MuteToggleButton> {
  String _selfUserId = '';
  String _authToken = '';
  bool _isMuted = false;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _selfUserId = prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
    _authToken = prefs.getString('token') ?? '';

    if (_selfUserId.isEmpty ||
        _authToken.isEmpty ||
        _selfUserId == widget.targetUserId) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final muted = await AuthService.instance.getMutedUsers(
        userId: _selfUserId,
        authToken: _authToken,
      );
      final isMuted = muted.any(
        (u) => (u['_id'] ?? u['id']).toString() == widget.targetUserId,
      );
      if (!mounted) return;
      setState(() {
        _isMuted = isMuted;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleMute() async {
    if (_submitting || _selfUserId.isEmpty || _authToken.isEmpty) return;
    setState(() => _submitting = true);
    try {
      if (_isMuted) {
        await AuthService.instance.unmuteUser(
          userId: _selfUserId,
          authToken: _authToken,
          targetUserId: widget.targetUserId,
        );
      } else {
        await AuthService.instance.muteUser(
          userId: _selfUserId,
          authToken: _authToken,
          targetUserId: widget.targetUserId,
        );
      }
      if (!mounted) return;
      setState(() => _isMuted = !_isMuted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isMuted ? 'User muted' : 'User unmuted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update mute: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _selfUserId == widget.targetUserId) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      onPressed: _submitting ? null : _toggleMute,
      icon: Icon(
        _isMuted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
      ),
      label: Text(_isMuted ? 'Unmute' : 'Mute'),
    );
  }
}

class _BlockToggleButton extends StatefulWidget {
  final String targetUserId;

  const _BlockToggleButton({required this.targetUserId});

  @override
  State<_BlockToggleButton> createState() => _BlockToggleButtonState();
}

class _BlockToggleButtonState extends State<_BlockToggleButton> {
  String _selfUserId = '';
  String _authToken = '';
  bool _isBlocked = false;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _selfUserId = prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
    _authToken = prefs.getString('token') ?? '';

    if (_selfUserId.isEmpty ||
        _authToken.isEmpty ||
        _selfUserId == widget.targetUserId) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final blocked = await AuthService.instance.getBlockedUsers(
        userId: _selfUserId,
        authToken: _authToken,
      );
      final isBlocked = blocked.any(
        (u) => (u['_id'] ?? u['id']).toString() == widget.targetUserId,
      );
      if (!mounted) return;
      setState(() {
        _isBlocked = isBlocked;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (_submitting || _selfUserId.isEmpty || _authToken.isEmpty) return;
    setState(() => _submitting = true);
    try {
      if (_isBlocked) {
        await AuthService.instance.unblockUser(
          userId: _selfUserId,
          authToken: _authToken,
          targetUserId: widget.targetUserId,
        );
      } else {
        await AuthService.instance.blockUser(
          userId: _selfUserId,
          authToken: _authToken,
          targetUserId: widget.targetUserId,
        );
      }
      if (!mounted) return;
      setState(() => _isBlocked = !_isBlocked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isBlocked ? 'User blocked' : 'User unblocked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update block: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _selfUserId == widget.targetUserId) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      onPressed: _submitting ? null : _toggleBlock,
      icon: Icon(_isBlocked ? Icons.lock_open_rounded : Icons.block_outlined),
      label: Text(_isBlocked ? 'Unblock' : 'Block'),
    );
  }
}

class _ReportUserSheet extends StatefulWidget {
  final String userName;

  const _ReportUserSheet({required this.userName});

  @override
  State<_ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<_ReportUserSheet> {
  static const _reasons = <String>[
    'Harassment or bullying',
    'Spam or scam',
    'Hate or abuse',
    'Impersonation',
    'Privacy violation',
    'Other',
  ];

  final _detailsController = TextEditingController();
  String _selectedReason = _reasons.first;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _ReportDraft(
        reason: _selectedReason,
        details: _detailsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report ${widget.userName}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Tell us what happened so we can review it.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              items: _reasons
                  .map(
                    (reason) =>
                        DropdownMenuItem(value: reason, child: Text(reason)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedReason = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailsController,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Submit report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

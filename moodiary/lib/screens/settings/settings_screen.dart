import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/local_notifications_service.dart';
import '../../services/theme_controller.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/transitions.dart';
import '../../widgets/glass.dart';
import '../companion/companion_screen.dart';
import '../account/account_management_screen.dart';
import '../notifications/notifications_screen.dart';
import '../legal/legal_screens.dart';

class SettingsScreen extends StatefulWidget {
  final String userName;
  final bool showAppBar;
  const SettingsScreen({
    super.key,
    required this.userName,
    this.showAppBar = true,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _dailyKey = 'settings_daily_reminders';
  static const _weeklyKey = 'settings_weekly_summary';
  static const _dataSaverKey = 'settings_data_saver';

  ThemeMode _themeMode = ThemeController.instance.mode;
  bool _dailyReminders = true;
  bool _weeklySummary = false;
  bool _dataSaver = false;
  bool _loading = true;
  bool _sendingWeeklyTest = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final daily = prefs.getBool(_dailyKey) ?? true;
    final weekly = prefs.getBool(_weeklyKey) ?? false;
    final dataSaver = prefs.getBool(_dataSaverKey) ?? false;
    setState(() {
      _dailyReminders = daily;
      _weeklySummary = weekly;
      _dataSaver = dataSaver;
      _themeMode = ThemeController.instance.mode;
      _loading = false;
    });
    await DataSaverMode.setEnabled(dataSaver);
    await _updateNotificationSchedule(_dailyKey, daily, silent: true);
    await _updateNotificationSchedule(_weeklyKey, weekly, silent: true);
  }

  Future<void> _updateBool(String key, bool value) async {
    setState(() {
      switch (key) {
        case _dailyKey:
          _dailyReminders = value;
          break;
        case _weeklyKey:
          _weeklySummary = value;
          break;
        case _dataSaverKey:
          _dataSaver = value;
          break;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (key == _dataSaverKey) {
      await DataSaverMode.setEnabled(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Data Saver enabled: reduced motion and lighter transitions.'
                  : 'Data Saver disabled: full animations restored.',
            ),
          ),
        );
      }
      return;
    }
    if (key == _dailyKey || key == _weeklyKey) {
      await _updateNotificationSchedule(key, value);
    }
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await ThemeController.instance.setMode(mode);
  }

  Future<void> _updateNotificationSchedule(
    String key,
    bool enabled, {
    bool silent = false,
  }) async {
    if (key == _dailyKey) {
      if (!enabled) {
        await LocalNotificationsService.instance.cancelDailyReminder();
        return;
      }
      final granted = await LocalNotificationsService.instance
          .ensurePermissions();
      if (!granted) {
        await _disableNotificationKey(_dailyKey);
        if (!silent) _showPermissionSnack();
        return;
      }
      await LocalNotificationsService.instance.scheduleDailyReminder();
      return;
    }
    if (key == _weeklyKey) {
      if (!enabled) {
        await LocalNotificationsService.instance.cancelWeeklySummary();
        return;
      }
      final granted = await LocalNotificationsService.instance
          .ensurePermissions();
      if (!granted) {
        await _disableNotificationKey(_weeklyKey);
        if (!silent) _showPermissionSnack();
        return;
      }
      await LocalNotificationsService.instance.scheduleWeeklySummary();
      final prefs = await SharedPreferences.getInstance();
      final userId =
          prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
      final token = prefs.getString('token') ?? '';
      if (userId.isNotEmpty && token.isNotEmpty) {
        try {
          await AuthService.instance.sendWeeklyReportEmail(
            userId: userId,
            authToken: token,
          );
          if (!silent && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Weekly report email sent.')),
            );
          }
        } catch (e) {
          if (!silent && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not send weekly report: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _disableNotificationKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == _dailyKey) {
      setState(() => _dailyReminders = false);
    } else if (key == _weeklyKey) {
      setState(() => _weeklySummary = false);
    }
    await prefs.setBool(key, false);
  }

  void _showPermissionSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Enable notification permissions in system settings to receive reminders.',
        ),
      ),
    );
  }

  Future<void> _sendWeeklyReportTest() async {
    if (_sendingWeeklyTest) return;
    setState(() => _sendingWeeklyTest = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId =
          prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
      final token = prefs.getString('token') ?? '';
      if (userId.isEmpty || token.isEmpty) {
        throw AuthException('Please log in again to send test email.');
      }
      await AuthService.instance.sendWeeklyReportEmail(
        userId: userId,
        authToken: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test weekly report email sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send test email: $e')));
    } finally {
      if (mounted) setState(() => _sendingWeeklyTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final topInset = MediaQuery.of(context).padding.top;
    final listPadding = widget.showAppBar
        ? const EdgeInsets.fromLTRB(20, 16, 20, 32)
        : EdgeInsets.fromLTRB(20, topInset + 12, 20, 32);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: const Text('Settings'), centerTitle: true)
          : null,
      body: ListView(
        padding: listPadding,
        children: [
          _SectionHeader(label: 'Appearance'),
          GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(20),
            backgroundColor: context.mdGlassSurface,
            borderColor: context.mdGlassBorder,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 360;
                      final labelStyle = TextStyle(
                        fontSize: isCompact ? 12 : 14,
                        fontWeight: FontWeight.w600,
                      );
                      final iconSize = isCompact ? 18.0 : 20.0;
                      return SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(
                            EdgeInsets.symmetric(
                              horizontal: isCompact ? 8 : 12,
                              vertical: isCompact ? 6 : 10,
                            ),
                          ),
                          textStyle: WidgetStateProperty.all(labelStyle),
                        ),
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(
                              Icons.phone_iphone_outlined,
                              size: iconSize,
                            ),
                            label: Text(isCompact ? 'Sys' : 'System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.wb_sunny_outlined, size: iconSize),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.nightlight_round, size: iconSize),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: <ThemeMode>{_themeMode},
                        onSelectionChanged: (selection) =>
                            _updateTheme(selection.first),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'Notifications'),
          GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(20),
            backgroundColor: context.mdGlassSurface,
            borderColor: context.mdGlassBorder,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  title: const Text('Daily reminders'),
                  subtitle: const Text('Receive gentle pings to finish tasks'),
                  value: _dailyReminders,
                  onChanged: (value) => _updateBool(_dailyKey, value),
                ),
                const Divider(height: 0),
                SwitchListTile.adaptive(
                  title: const Text('Weekly summary email'),
                  subtitle: const Text(
                    'Get a recap of your moods and activities',
                  ),
                  value: _weeklySummary,
                  onChanged: (value) => _updateBool(_weeklyKey, value),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: _sendingWeeklyTest
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mark_email_read_outlined),
                  title: const Text('Send test weekly report now'),
                  subtitle: const Text('Verify your email delivery instantly'),
                  enabled: !_sendingWeeklyTest,
                  onTap: _sendingWeeklyTest ? null : _sendWeeklyReportTest,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'Account'),
          GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(20),
            backgroundColor: context.mdGlassSurface,
            borderColor: context.mdGlassBorder,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Account management'),
                  subtitle: const Text('Change password and account settings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      FadeSlideRoute(page: const AccountManagementScreen()),
                    );
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Notification history'),
                  subtitle: const Text('Review previous notifications'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(
                      context,
                    ).push(FadeSlideRoute(page: const NotificationsScreen()));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'Companion & Data'),
          GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(20),
            backgroundColor: context.mdGlassSurface,
            borderColor: context.mdGlassBorder,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.pets_rounded),
                  title: const Text('Choose companion'),
                  subtitle: const Text(
                    'Switch who guides you through the journey',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      FadeSlideRoute(
                        page: CompanionScreen(userName: widget.userName),
                      ),
                    );
                  },
                ),
                const Divider(height: 0),
                SwitchListTile.adaptive(
                  title: const Text('Data saver mode'),
                  subtitle: const Text('Reduce animation and network usage'),
                  value: _dataSaver,
                  onChanged: (value) => _updateBool(_dataSaverKey, value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'About'),
          GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(20),
            backgroundColor: context.mdGlassSurface,
            borderColor: context.mdGlassBorder,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Version'),
                  subtitle: const Text('v1.0.0'),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    Navigator.of(
                      context,
                    ).push(FadeSlideRoute(page: const PrivacyPolicyScreen()));
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of service'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    Navigator.of(
                      context,
                    ).push(FadeSlideRoute(page: const TermsOfServiceScreen()));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          letterSpacing: 0.6,
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

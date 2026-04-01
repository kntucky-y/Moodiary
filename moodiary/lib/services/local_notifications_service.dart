import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationsService {
  LocalNotificationsService._();

  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _dailyId = 1001;
  static const _weeklyId = 1002;
  static const _channelId = 'moodiary_reminders';
  static const _channelName = 'Moodiary Reminders';
  static const _channelDesc = 'Daily and weekly wellbeing nudges';

  bool _initialized = false;
  bool _timezoneReady = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const windows = WindowsInitializationSettings(
      appName: 'Moodiary',
      appUserModelId: 'com.moodiary.app',
      guid: '4ef6c957-6a87-4c8b-8d67-7da73cb5c4e9',
    );
    final settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: windows,
    );
    await _plugin.initialize(settings: settings);
    await _configureTimeZone();
    _initialized = true;
  }

  Future<void> _configureTimeZone() async {
    if (_timezoneReady) return;
    tz.initializeTimeZones();
    String location = 'UTC';
    try {
      location = await FlutterNativeTimezone.getLocalTimezone();
    } catch (_) {}
    try {
      tz.setLocalLocation(tz.getLocation(location));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _timezoneReady = true;
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Moodiary',
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<bool> ensurePermissions() async {
    await initialize();
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidPlugin?.requestNotificationsPermission() ?? true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      return await macPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    return true;
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekday(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> scheduleDailyReminder() async {
    await initialize();
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: 'Stay on track',
      body: 'Complete at least one wellbeing task today.',
      notificationDetails: _details,
      scheduledDate: _nextInstanceOfTime(20, 0),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyReminder() async {
    await _plugin.cancel(id: _dailyId);
  }

  Future<void> scheduleWeeklySummary() async {
    await initialize();
    await _plugin.zonedSchedule(
      id: _weeklyId,
      title: 'Weekly reflection',
      body: 'Review your moods and journal before the week ends.',
      notificationDetails: _details,
      scheduledDate: _nextInstanceOfWeekday(DateTime.sunday, 20, 0),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancelWeeklySummary() async {
    await _plugin.cancel(id: _weeklyId);
  }

  Future<void> refresh({
    required bool dailyEnabled,
    required bool weeklyEnabled,
  }) async {
    if (dailyEnabled) {
      await scheduleDailyReminder();
    } else {
      await cancelDailyReminder();
    }
    if (weeklyEnabled) {
      await scheduleWeeklySummary();
    } else {
      await cancelWeeklySummary();
    }
  }

  Future<void> cancelAllScheduled() async {
    await _plugin.cancel(id: _dailyId);
    await _plugin.cancel(id: _weeklyId);
  }

  Future<void> showInstant({
    required String title,
    required String message,
  }) async {
    await initialize();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
      notificationDetails: _details,
    );
  }
}

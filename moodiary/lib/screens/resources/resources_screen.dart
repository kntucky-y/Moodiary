import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/local_notifications_service.dart';
import '../../services/realtime_notifications.dart';
import '../../services/session_store.dart';
import '../../services/theme_controller.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/transitions.dart';
import '../../utils/user_cache.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/glass.dart';
import '../app_shell.dart';
import '../calendar/calendar_screen.dart';
import '../companion/companion_screen.dart';
import '../journal/journal_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';

class ResourcesScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  final ShellTabSelector? onShellTabSelected;
  final bool showTopNav;
  final ShellNavVisibilitySetter? onShellNavVisibilityChanged;

  const ResourcesScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
    this.onShellTabSelected,
    this.showTopNav = true,
    this.onShellNavVisibilityChanged,
  });

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  bool _sidebarOpen = false;
  bool _headerCollapsed = false;
  LatLng? _pendingMapCenter;
  double _pendingMapZoom = 13;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  final List<String> _categories = [
    'All',
    'Mental Health',
    'Mindfulness',
    'Wellness',
    'Social',
  ];
  final List<int> _radiusOptions = [2000, 5000, 10000, 20000];

  String _selectedCategory = 'All';
  int _radiusMeters = 5000;
  bool _loadingResources = false;
  bool _loadingClinics = false;
  String? _resourcesError;
  String? _clinicError;
  LatLng? _currentCenter;
  List<Map<String, dynamic>> _resources = const [];
  List<Map<String, dynamic>> _clinics = const [];
  Map<String, dynamic>? _selectedClinic;
  List<Map<String, dynamic>> _moodLinks = const [];
  String? _analysisScope;

  @override
  void initState() {
    super.initState();
    _loadResources();
    _bootstrapNearbyClinics();
    _realtimeSub = RealtimeNotifications.instance.stream.listen(
      _handleRealtimeEvent,
    );
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _handleRealtimeEvent(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    if (type == 'mood_analysis_updated') {
      if (!_loadingResources && mounted) {
        _loadResources();
      }
    }
  }

  Future<void> _loadResources() async {
    setState(() {
      _loadingResources = true;
      _resourcesError = null;
    });

    try {
      final payload = await AuthService.instance.getResources(
        authToken: await SessionStore.instance.readToken(),
      );
      final rawResources = payload['resources'] as List<dynamic>? ?? const [];
      final rawMoodLinks = payload['moodLinks'] as List<dynamic>? ?? const [];
      final analysisScope = payload['analysisScope']?.toString();
      if (!mounted) return;
      setState(() {
        _resources = rawResources.cast<Map<String, dynamic>>();
        _moodLinks = rawMoodLinks.cast<Map<String, dynamic>>();
        _analysisScope = analysisScope;
        _loadingResources = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resourcesError = error.toString();
        _resources = const [];
        _moodLinks = const [];
        _analysisScope = null;
        _loadingResources = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadResources(), _bootstrapNearbyClinics()]);
  }

  Uri? _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final withoutMarkdown = trimmed
        .replaceAll(RegExp(r'^<|>$'), '')
        .replaceFirst(RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$'), r'$2')
        .trim();
    final withoutTrailing = withoutMarkdown.replaceFirst(
      RegExp(r'[\)\],.;!?]+$'),
      '',
    );

    String withScheme =
        withoutTrailing.startsWith('http://') ||
            withoutTrailing.startsWith('https://')
        ? withoutTrailing
        : 'https://$withoutTrailing';

    for (var i = 0; i < 3; i++) {
      final parsed = Uri.tryParse(withScheme);
      if (parsed == null) return null;
      final redirectParam =
          parsed.queryParameters['url'] ??
          parsed.queryParameters['u'] ??
          parsed.queryParameters['q'] ??
          parsed.queryParameters['target'] ??
          parsed.queryParameters['dest'] ??
          parsed.queryParameters['destination'] ??
          parsed.queryParameters['redirect'];
      if (redirectParam == null) {
        return (parsed.scheme == 'http' || parsed.scheme == 'https')
            ? parsed
            : null;
      }

      final decoded = Uri.decodeFull(redirectParam).trim();
      if (!(decoded.startsWith('http://') || decoded.startsWith('https://'))) {
        return (parsed.scheme == 'http' || parsed.scheme == 'https')
            ? parsed
            : null;
      }
      withScheme = decoded;
    }

    final parsed = Uri.tryParse(withScheme);
    if (parsed == null) return null;
    return (parsed.scheme == 'http' || parsed.scheme == 'https')
        ? parsed
        : null;
  }

  void _showLaunchError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open that link right now.')),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = _normalizeUrl(url);
    if (uri == null) return;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showLaunchError();
      }
    } catch (_) {
      _showLaunchError();
    }
  }

  Future<void> _launchPhone(String phone) async {
    final sanitized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (sanitized.isEmpty) return;
    final uri = Uri.parse('tel:$sanitized');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<LatLng> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled on this device.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission is required to show nearby clinics.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it from app settings.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  Future<void> _bootstrapNearbyClinics() async {
    try {
      final current = await _getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _currentCenter = current;
        _clinicError = null;
      });
      _moveMapSafely(current, _zoomForRadius(_radiusMeters));
      await _loadNearbyClinics(center: current);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clinicError = error.toString();
        _clinics = const [];
        _selectedClinic = null;
      });
    }
  }

  Future<void> _loadNearbyClinics({LatLng? center}) async {
    final queryCenter = center ?? _currentCenter;
    if (queryCenter == null) return;

    setState(() {
      _loadingClinics = true;
      _clinicError = null;
    });

    try {
      final payload = await AuthService.instance.getNearbyClinics(
        latitude: queryCenter.latitude,
        longitude: queryCenter.longitude,
        radiusMeters: _radiusMeters,
        limit: 15,
      );

      if (!mounted) return;
      final rawClinics = payload['clinics'] as List<dynamic>? ?? const [];
      setState(() {
        _clinics = rawClinics.cast<Map<String, dynamic>>();
        _selectedClinic = _clinics.isNotEmpty ? _clinics.first : null;
        _loadingClinics = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clinicError = error.toString();
        _clinics = const [];
        _selectedClinic = null;
        _loadingClinics = false;
      });
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    try {
      final current = await _getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _currentCenter = current;
        _clinicError = null;
      });
      _moveMapSafely(current, _zoomForRadius(_radiusMeters));
      await _loadNearbyClinics(center: current);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clinicError = error.toString();
      });
    }
  }

  Future<void> _searchAroundPoint(LatLng center) async {
    if (!mounted) return;
    setState(() {
      _currentCenter = center;
      _clinicError = null;
    });
    _moveMapSafely(center, _zoomForRadius(_radiusMeters));
    await _loadNearbyClinics(center: center);
  }

  double _zoomForRadius(int radiusMeters) {
    if (radiusMeters <= 3000) return 13.5;
    if (radiusMeters <= 6000) return 12.5;
    if (radiusMeters <= 10000) return 11.5;
    if (radiusMeters <= 20000) return 10.5;
    return 10.0;
  }

  void _updateMapZoomForRadius() {
    final center = _currentCenter ?? _pendingMapCenter;
    if (center == null) return;
    _moveMapSafely(center, _zoomForRadius(_radiusMeters));
  }

  LatLng _clinicPoint(Map<String, dynamic> clinic) {
    final latitude = (clinic['latitude'] as num).toDouble();
    final longitude = (clinic['longitude'] as num).toDouble();
    return LatLng(latitude, longitude);
  }

  double _distanceKm(Map<String, dynamic> clinic) {
    final current = _currentCenter;
    if (current == null) return 0;
    final clinicPoint = _clinicPoint(clinic);
    final meters = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      clinicPoint.latitude,
      clinicPoint.longitude,
    );
    return meters / 1000;
  }

  void _moveMapSafely(LatLng center, double zoom) {
    if (!_isMapReady) {
      _pendingMapCenter = center;
      _pendingMapZoom = zoom;
      return;
    }

    _mapController.move(center, zoom);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final collapsed =
        notification.metrics.pixels > context.mdHeaderCollapseOffset;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
    return false;
  }

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m away';
    }
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km away';
  }

  double _responsiveWidth({
    required double mobileFraction,
    required double min,
    required double max,
  }) {
    final width = MediaQuery.of(context).size.width;
    final candidate = width * mobileFraction;
    return candidate.clamp(min, max).toDouble();
  }

  String _todayStr() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  void _setSidebarOpen(bool open) {
    if (_sidebarOpen == open) return;
    setState(() => _sidebarOpen = open);
    widget.onShellNavVisibilityChanged?.call(open);
  }

  void _openSidebar() => _setSidebarOpen(true);

  void _closeSidebar() => _setSidebarOpen(false);

  void _openScreen(Widget page) {
    _closeSidebar();
    Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  void _openShellTab(MoodiaryTab tab, {bool fromSidebar = false}) {
    _closeSidebar();
    final onShellTabSelected = widget.onShellTabSelected;
    if (onShellTabSelected != null) {
      onShellTabSelected(tab, fromSidebar: false);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          initialTab: tab,
          initialHideTopNav: false,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _logout() async {
    _closeSidebar();
    final prefs = await SharedPreferences.getInstance();
    await UserCache.clear(prefs);
    await SessionStore.instance.clearSession();
    await prefs.remove('user_name');
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

  Widget _buildClinicPreviewCards() {
    if (_clinics.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 124,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        scrollDirection: Axis.horizontal,
        itemCount: _clinics.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final clinic = _clinics[index];
          final isSelected = _selectedClinic == clinic;
          final cardWidth = _responsiveWidth(
            mobileFraction: 0.64,
            min: 220,
            max: 320,
          );
          return SizedBox(
            width: cardWidth,
            child: GlassCard(
              borderRadius: BorderRadius.circular(16),
              backgroundColor: isSelected
                  ? context.mdAccentPurple.withValues(alpha: 0.2)
                  : context.mdGlassSurface,
              borderColor: isSelected
                  ? context.mdAccentPurple
                  : context.mdGlassBorder,
              padding: const EdgeInsets.all(12),
              onTap: () {
                setState(() => _selectedClinic = clinic);
                _moveMapSafely(_clinicPoint(clinic), 14.5);
                _showClinicDetails(clinic);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clinic['name'] as String? ?? 'Clinic',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.mdPrimaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatDistance(_distanceKm(clinic)),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.mdSecondaryText,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: context.mdSecondaryText,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          clinic['address'] as String? ?? 'Address unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: context.mdSecondaryText),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showClinicDetails(Map<String, dynamic> clinic) async {
    final distanceKm = _distanceKm(clinic);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.mdOverlayBarrier,
      builder: (context) {
        return SafeArea(
          child: GlassContainer(
            blurSigma: context.mdGlassBlurMedium,
            borderRadius: BorderRadius.circular(context.mdRadiusXl),
            backgroundColor: context.mdGlassSurfaceStrong,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clinic['name'] as String? ?? 'Clinic',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  clinic['description'] as String? ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.place_outlined,
                  text: clinic['address'] as String? ?? 'Address unavailable',
                ),
                _InfoRow(
                  icon: Icons.straighten,
                  text: _formatDistance(distanceKm),
                ),
                if ((clinic['openingHours'] as String? ?? '').trim().isNotEmpty)
                  _InfoRow(
                    icon: Icons.schedule,
                    text: clinic['openingHours'] as String,
                  ),
                if ((clinic['phone'] as String? ?? '').trim().isNotEmpty)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    text: clinic['phone'] as String,
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _confirmClinicAction(
                            title:
                                'Call ${clinic['name'] as String? ?? 'Clinic'}',
                            description: clinic['phone'] as String? ?? '',
                            address: clinic['address'] as String? ?? '',
                            actionLabel: 'Call',
                            onAction: () =>
                                _launchPhone(clinic['phone'] as String? ?? ''),
                          );
                        },
                        icon: const Icon(Icons.call),
                        label: const Text('Call'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _confirmClinicAction(
                            title: 'Open website',
                            description: clinic['website'] as String? ?? '',
                            address: clinic['address'] as String? ?? '',
                            actionLabel: 'Open',
                            onAction: () =>
                                _launchUrl(clinic['website'] as String? ?? ''),
                          );
                        },
                        icon: const Icon(Icons.public),
                        label: const Text('Website'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmClinicAction({
    required String title,
    required String description,
    required String address,
    required String actionLabel,
    required VoidCallback onAction,
  }) async {
    final trimmedDescription = description.trim();
    final trimmedAddress = address.trim();
    final messageParts = <String>[];
    if (trimmedDescription.isNotEmpty) {
      messageParts.add(trimmedDescription);
    }
    if (trimmedAddress.isNotEmpty) {
      messageParts.add(trimmedAddress);
    }
    final message = messageParts.join('\n');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message.isEmpty ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onAction();
    }
  }

  List<Map<String, dynamic>> get _filteredResources {
    if (_selectedCategory == 'All') return _resources;
    return _resources.where((resource) {
      final category = resource['category']?.toString() ?? '';
      return category.toLowerCase() == _selectedCategory.toLowerCase();
    }).toList();
  }

  List<Map<String, dynamic>> get _featuredResources {
    return _filteredResources
        .where((resource) => resource['featured'] as bool? ?? false)
        .toList();
  }

  List<Map<String, dynamic>> get _dailyRandomResources {
    if (_resources.isEmpty) return const [];
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final shuffled = List<Map<String, dynamic>>.from(_resources)
      ..shuffle(Random(seed));
    return shuffled.take(3).toList();
  }

  Future<void> _setCategory(String category) async {
    setState(() => _selectedCategory = category);
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            onSelected: (_) => _setCategory(category),
            selectedColor: context.mdAccentPurple.withValues(alpha: 0.18),
            backgroundColor: context.mdSurface,
            labelStyle: TextStyle(
              color: isSelected
                  ? context.mdAccentPurple
                  : context.mdPrimaryText,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(
              color: isSelected
                  ? context.mdAccentPurple
                  : context.mdInputBorder,
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: _categories.length,
      ),
    );
  }

  Widget _buildMoodLinksSection() {
    if (_loadingResources) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _LoadingCard(),
      );
    }

    if (_moodLinks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _EmptyStateCard(
          icon: Icons.auto_awesome_outlined,
          title: 'No mood links yet',
          message:
              'Analyze your day or week from the Home tab to see personalized links here.',
        ),
      );
    }

    return Column(
      children: _moodLinks.map((link) {
        final title = (link['title'] ?? '').toString();
        final url = (link['url'] ?? '').toString();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: GlassCard(
            borderRadius: BorderRadius.circular(18),
            backgroundColor: context.mdGlassSurface,
            borderColor: context.mdGlassBorder,
            onTap: () => _launchUrl(url),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: context.mdAccentPurple,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.mdPrimaryText,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: context.mdSecondaryText,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeaturedGuidesSection() {
    if (_featuredResources.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 226,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _featuredResources.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final resource = _featuredResources[index];
          return _GuideCard(
            resource: resource,
            onTap: () => _launchUrl(resource['url'] as String? ?? ''),
          );
        },
      ),
    );
  }

  List<Widget> _buildDailyRandomCards() {
    if (_resourcesError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ErrorStateCard(
            icon: Icons.auto_stories_outlined,
            title: 'Resources could not load',
            message: _resourcesError!,
            actionLabel: 'Retry',
            onAction: _loadResources,
          ),
        ),
      ];
    }

    if (_loadingResources) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _LoadingCard(),
        ),
      ];
    }

    final picks = _dailyRandomResources;
    if (picks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _EmptyStateCard(
            icon: Icons.auto_stories_outlined,
            title: 'No resources yet',
            message: 'Check back after your next mood check-in.',
          ),
        ),
      ];
    }

    return picks
        .map(
          (resource) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: GlassCard(
              borderRadius: BorderRadius.circular(20),
              backgroundColor: context.mdGlassSurface,
              borderColor: context.mdGlassBorder,
              onTap: () => _launchUrl(resource['url'] as String? ?? ''),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resource['title'] as String? ?? '',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.mdPrimaryText,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resource['category'] as String? ?? '',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: context.mdSecondaryText),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 20,
                        color: context.mdSecondaryText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    resource['description'] as String? ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.mdSecondaryText,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        )
        .toList();
  }

  Widget _buildNearbyClinicsSection() {
    final center = _currentCenter;

    if (_clinicError != null && center == null) {
      return _ErrorStateCard(
        icon: Icons.local_hospital_outlined,
        title: 'Clinic map unavailable',
        message: _clinicError!,
        actionLabel: 'Try again',
        onAction: _bootstrapNearbyClinics,
      );
    }

    if (center == null) {
      return const _LoadingCard();
    }

    final markers = <Marker>[
      Marker(
        point: center,
        width: 44,
        height: 44,
        child: Icon(Icons.my_location, color: context.mdAccentPurple, size: 28),
      ),
      ..._clinics.map(
        (clinic) => Marker(
          point: _clinicPoint(clinic),
          width: 44,
          height: 44,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _selectedClinic = clinic);
              _showClinicDetails(clinic);
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  Icons.location_pin,
                  color: _selectedClinic == clinic
                      ? context.mdAccentPurple
                      : context.mdSecondaryText,
                  size: 34,
                ),
              ),
            ),
          ),
        ),
      ),
    ];

    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(context.mdRadiusXl),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby clinics',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.mdPrimaryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loadingClinics
                            ? 'Finding the nearest support options now.'
                            : 'Tap the map or a clinic card for details.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.mdSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _centerOnCurrentLocation,
                  icon: const Icon(Icons.my_location_outlined),
                  label: const Text('Recenter'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_clinics.length} clinics within ${_radiusMeters ~/ 1000} km',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.mdSecondaryText,
                    ),
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: 'Search radius',
                  initialValue: _radiusMeters,
                  onSelected: (value) {
                    setState(() => _radiusMeters = value);
                    _updateMapZoomForRadius();
                    _loadNearbyClinics();
                  },
                  itemBuilder: (context) => _radiusOptions
                      .map(
                        (radius) => PopupMenuItem<int>(
                          value: radius,
                          child: Text('${radius ~/ 1000} km radius'),
                        ),
                      )
                      .toList(),
                  child: Chip(
                    label: Text('${_radiusMeters ~/ 1000} km'),
                    avatar: const Icon(Icons.tune, size: 18),
                  ),
                ),
              ],
            ),
          ),
          if (_clinicError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: GlassContainer(
                  blurSigma: context.mdGlassBlurMedium,
                  borderRadius: BorderRadius.circular(16),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.5),
                  borderColor: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.45),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_clinicError!)),
                      TextButton(
                        onPressed: _loadNearbyClinics,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 260,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 13,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onTap: (tapPosition, point) {
                      if (_selectedClinic != null) {
                        setState(() => _selectedClinic = null);
                      }
                    },
                    onLongPress: (tapPosition, point) {
                      _searchAroundPoint(point);
                    },
                    onMapReady: () {
                      _isMapReady = true;
                      final pendingCenter = _pendingMapCenter;
                      if (pendingCenter != null) {
                        _mapController.move(pendingCenter, _pendingMapZoom);
                        _pendingMapCenter = null;
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.moodiary.app',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Tap markers for details. Long-press anywhere to search that area.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.mdSecondaryText),
            ),
          ),
          _buildClinicPreviewCards(),
        ],
      ),
    );
  }

  List<Widget> _buildResourceCards() {
    if (_resourcesError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ErrorStateCard(
            icon: Icons.auto_stories_outlined,
            title: 'Resources could not load',
            message: _resourcesError!,
            actionLabel: 'Retry',
            onAction: () {
              _loadResources();
            },
          ),
        ),
      ];
    }

    if (_loadingResources) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _LoadingCard(),
        ),
      ];
    }

    final resources = _filteredResources;
    if (resources.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _EmptyStateCard(
            icon: Icons.auto_stories_outlined,
            title: 'No guides in this category',
            message:
                'Try a different filter to see more self-care articles and support links.',
          ),
        ),
      ];
    }

    return resources
        .map(
          (resource) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: GlassCard(
              borderRadius: BorderRadius.circular(20),
              backgroundColor: context.mdGlassSurface,
              borderColor: context.mdGlassBorder,
              onTap: () => _launchUrl(resource['url'] as String? ?? ''),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (resource['featured'] as bool? ?? false)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _SummaryChip(
                                  icon: Icons.star_rounded,
                                  label: 'Featured',
                                  compact: true,
                                ),
                              ),
                            Text(
                              resource['title'] as String? ?? '',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.mdPrimaryText,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resource['category'] as String? ?? '',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: context.mdSecondaryText),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        size: 20,
                        color: context.mdSecondaryText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    resource['description'] as String? ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.mdSecondaryText,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((resource['recommendationReason'] as String? ?? '')
                          .trim()
                          .isNotEmpty &&
                      (resource['recommendationReason'] as String? ?? '')
                              .trim() !=
                          'Suggested from your recent mood and journal patterns.') ...[
                    const SizedBox(height: 10),
                    _RecommendationReason(
                      text: resource['recommendationReason'] as String,
                    ),
                  ],
                ],
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final pagePadding = MediaQuery.of(context).size.width >= 700 ? 20.0 : 16.0;
    final headerHorizontalPadding = 20.0;
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;

    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: Stack(
        children: [
          Column(
            children: [
              if (widget.showTopNav)
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      headerHorizontalPadding,
                      10,
                      headerHorizontalPadding,
                      8,
                    ),
                    child: GlassContainer(
                      blurSigma: context.mdGlassBlurSmall,
                      borderRadius: BorderRadius.circular(22),
                      backgroundColor: context.mdGlassSurfaceStrong,
                      borderColor: context.mdGlassBorder,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: _openSidebar,
                                icon: Icon(
                                  Icons.menu,
                                  color: primaryText,
                                  size: 26,
                                ),
                                tooltip: 'Open menu',
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    _todayStr(),
                                    style: TextStyle(
                                      color: primaryText,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _refreshAll,
                                icon: Icon(
                                  Icons.refresh_rounded,
                                  color: primaryText,
                                  size: 22,
                                ),
                                tooltip: 'Refresh resources',
                              ),
                            ],
                          ),
                          AnimatedSize(
                            duration: context.mdHeaderCollapseDuration,
                            curve: Curves.easeOutCubic,
                            child: _headerCollapsed
                                ? const SizedBox.shrink()
                                : AnimatedOpacity(
                                    duration: context.mdHeaderFadeDuration,
                                    opacity: _headerCollapsed ? 0 : 1,
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Resources',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: primaryText,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Support that feels close, useful, and calm.',
                                            style: TextStyle(
                                              color: secondaryText,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: GlassContainer(
                            blurSigma: context.mdGlassBlurMedium,
                            margin: EdgeInsets.fromLTRB(
                              pagePadding,
                              4,
                              pagePadding,
                              8,
                            ),
                            borderRadius: BorderRadius.circular(
                              context.mdRadiusXl,
                            ),
                            backgroundColor: context.mdGlassSurface,
                            borderColor: context.mdGlassBorder,
                            padding: const EdgeInsets.all(18),
                            gradient: context.mdGlassHeroGradient,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    GlassContainer(
                                      blurSigma: context.mdGlassBlurSmall,
                                      borderRadius: BorderRadius.circular(16),
                                      backgroundColor: context.mdAccentPurple
                                          .withValues(alpha: 0.16),
                                      borderColor: context.mdGlassBorder,
                                      padding: const EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.auto_awesome_rounded,
                                        color: context.mdAccentPurple,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Browse curated guides and nearby clinic support.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: context.mdPrimaryText,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _SummaryChip(
                                      icon: Icons.menu_book_outlined,
                                      label:
                                          '${_filteredResources.length} guides',
                                    ),
                                    _SummaryChip(
                                      icon: Icons.local_hospital_outlined,
                                      label: '${_clinics.length} clinics',
                                    ),
                                    _SummaryChip(
                                      icon: Icons.place_outlined,
                                      label:
                                          '${_radiusMeters ~/ 1000} km radius',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _buildCategoryChips(),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pagePadding,
                              16,
                              pagePadding,
                              0,
                            ),
                            child: _SectionTitle(
                              title: 'Suggested links based on your mood',
                              subtitle: _analysisScope == 'week'
                                  ? 'Based on your weekly mood patterns.'
                                  : 'Based on how today is going.',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildMoodLinksSection()),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pagePadding,
                              22,
                              pagePadding,
                              0,
                            ),
                            child: _buildNearbyClinicsSection(),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pagePadding,
                              22,
                              pagePadding,
                              0,
                            ),
                            child: _SectionTitle(
                              title: 'Suggested guides',
                              subtitle:
                                  'Updated from your recent mood and journal patterns.',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _buildFeaturedGuidesSection(),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pagePadding,
                              22,
                              pagePadding,
                              0,
                            ),
                            child: _SectionTitle(
                              title: "Today's random picks",
                              subtitle: 'Three fresh resources each day.',
                            ),
                          ),
                        ),
                        ..._buildDailyRandomCards().map(
                          (child) => SliverToBoxAdapter(child: child),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
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
              activeSection: SidebarSection.resources,
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
              onNavigateJournal: () => _openScreen(
                JournalScreen(
                  userName: widget.userName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateFriends: () => _openShellTab(MoodiaryTab.buddies),
              onNavigateForums: () => _openShellTab(MoodiaryTab.forums),
              onNavigateResources: _closeSidebar,
              onNavigateSettings: () =>
                  _openScreen(SettingsScreen(userName: widget.userName)),
              onChangeCompanion: () =>
                  _openScreen(CompanionScreen(userName: widget.userName)),
              onLogout: _logout,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.mdPrimaryText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.mdSecondaryText,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;

  const _SummaryChip({
    required this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurSigma: context.mdGlassBlurSmall,
      borderRadius: BorderRadius.circular(999),
      backgroundColor: context.mdAccentPurple.withValues(alpha: 0.16),
      borderColor: context.mdGlassBorder,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: context.mdAccentPurple),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.mdPrimaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationReason extends StatelessWidget {
  final String text;

  const _RecommendationReason({required this.text});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurSigma: context.mdGlassBlurSmall,
      borderRadius: BorderRadius.circular(14),
      backgroundColor: context.mdAccentPurple.withValues(alpha: 0.12),
      borderColor: context.mdGlassBorder,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 14,
            color: context.mdAccentPurple,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.mdPrimaryText,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final Map<String, dynamic> resource;
  final VoidCallback onTap;

  const _GuideCard({required this.resource, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = (width * 0.7).clamp(230.0, 340.0);

    return SizedBox(
      width: cardWidth,
      child: GlassCard(
        borderRadius: BorderRadius.circular(20),
        backgroundColor: context.mdGlassSurface,
        borderColor: context.mdGlassBorder,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SummaryChip(
              icon: Icons.star_rounded,
              label: 'Featured',
              compact: true,
            ),
            const Spacer(),
            Text(
              resource['title'] as String? ?? '',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.mdPrimaryText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              resource['description'] as String? ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.mdSecondaryText,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if ((resource['recommendationReason'] as String? ?? '')
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 10),
              _RecommendationReason(
                text: resource['recommendationReason'] as String,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: context.mdAccentPurple),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.mdPrimaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.mdSecondaryText,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _ErrorStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: context.mdAccentPurple),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.mdPrimaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.mdSecondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

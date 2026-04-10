import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../theme/moodiary_colors.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  late Future<void> _locationBootstrapFuture;

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

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

  @override
  void initState() {
    super.initState();
    _loadResources();
    _locationBootstrapFuture = _bootstrapNearbyClinics();
  }

  Future<void> _loadResources() async {
    setState(() {
      _loadingResources = true;
      _resourcesError = null;
    });

    try {
      final payload = await AuthService.instance.getResources();
      final rawResources = payload['resources'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _resources = rawResources.cast<Map<String, dynamic>>();
        _loadingResources = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resourcesError = error.toString();
        _resources = const [];
        _loadingResources = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadResources(), _bootstrapNearbyClinics()]);
  }

  Future<void> _launchUrl(String url) async {
    if (url.trim().isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
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
      _mapController.move(current, 13);
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
        limit: 30,
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
      _mapController.move(current, 13);
      await _loadNearbyClinics(center: current);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clinicError = error.toString();
      });
    }
  }

  LatLng _clinicPoint(Map<String, dynamic> clinic) {
    final latitude = (clinic['latitude'] as num).toDouble();
    final longitude = (clinic['longitude'] as num).toDouble();
    return LatLng(latitude, longitude);
  }

  double _distanceKm(Map<String, dynamic> clinic) {
    final current = _currentCenter;
    if (current == null) return 0;
    return _distance.as(LengthUnit.Kilometer, current, _clinicPoint(clinic));
  }

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m away';
    }
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km away';
  }

  Future<void> _showClinicDetails(Map<String, dynamic> clinic) async {
    final distanceKm = _distanceKm(clinic);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                          _launchPhone(clinic['phone'] as String? ?? '');
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
                          _launchUrl(clinic['website'] as String? ?? '');
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

  Widget _buildFeaturedGuidesSection() {
    if (_featuredResources.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 176,
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

  Widget _buildNearbyClinicsSection() {
    final center = _currentCenter;

    if (_clinicError != null && center == null) {
      return _ErrorStateCard(
        icon: Icons.location_off_outlined,
        title: 'Nearby clinics unavailable',
        message: _clinicError!,
        actionLabel: 'Try again',
        onAction: _bootstrapNearbyClinics,
      );
    }

    if (center == null) {
      return FutureBuilder<void>(
        future: _locationBootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingCard();
          }
          return _ErrorStateCard(
            icon: Icons.place_outlined,
            title: 'Location not ready',
            message:
                'Enable location access to see nearby mental health clinics on the map.',
            actionLabel: 'Try again',
            onAction: _bootstrapNearbyClinics,
          );
        },
      );
    }

    final markers = <Marker>[
      Marker(
        point: center,
        width: 44,
        height: 44,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
      ),
      ..._clinics.map(
        (clinic) => Marker(
          point: _clinicPoint(clinic),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedClinic = clinic);
              _showClinicDetails(clinic);
            },
            child: Icon(
              Icons.location_pin,
              color: _selectedClinic == clinic
                  ? context.mdAccentPurple
                  : Colors.redAccent,
              size: 34,
            ),
          ),
        ),
      ),
    ];

    return Card(
      elevation: 0,
      color: context.mdSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: context.mdInputBorder),
      ),
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
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
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
              'Tap a pin or clinic card to open call, website, and address details.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.mdSecondaryText),
            ),
          ),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Card(
              elevation: 0,
              color: context.mdSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: context.mdInputBorder),
              ),
              child: InkWell(
                onTap: () => _launchUrl(resource['url'] as String? ?? ''),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                                const SizedBox(height: 4),
                                Text(
                                  resource['category'] as String? ?? '',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: context.mdSecondaryText,
                                      ),
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
                      const SizedBox(height: 12),
                      Text(
                        resource['description'] as String? ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.mdSecondaryText,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mdScaffold,
      appBar: AppBar(
        title: const Text('Resources'),
        centerTitle: false,
        backgroundColor: context.mdScaffold,
        foregroundColor: context.mdPrimaryText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [context.mdSecondarySurface, context.mdSurface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: context.mdCardGlow,
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: context.mdInputBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.mdAccentPurple.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: context.mdAccentPurple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Support that feels close, useful, and calm.',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: context.mdPrimaryText,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Browse curated self-help guides or open the map to find nearby mental health clinics without leaving the app.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.mdSecondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SummaryChip(
                          icon: Icons.menu_book_outlined,
                          label: '${_filteredResources.length} guides',
                        ),
                        _SummaryChip(
                          icon: Icons.local_hospital_outlined,
                          label: '${_clinics.length} clinics',
                        ),
                        _SummaryChip(
                          icon: Icons.place_outlined,
                          label: '${_radiusMeters ~/ 1000} km radius',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildCategoryChips()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: _SectionTitle(
                  title: 'Featured guides',
                  subtitle: 'Curated reads for quick support and coping tools.',
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildFeaturedGuidesSection()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: _buildNearbyClinicsSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: _SectionTitle(
                  title: 'All resources',
                  subtitle: _selectedCategory == 'All'
                      ? 'Everything available right now.'
                      : 'Filtered to $_selectedCategory.',
                ),
              ),
            ),
            ..._buildResourceCards().map(
              (child) => SliverToBoxAdapter(child: child),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
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
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.mdSecondaryText,
            height: 1.35,
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: context.mdAccentPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
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

class _GuideCard extends StatelessWidget {
  final Map<String, dynamic> resource;
  final VoidCallback onTap;

  const _GuideCard({required this.resource, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        elevation: 0,
        color: context.mdSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.mdInputBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: context.mdSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.mdInputBorder),
      ),
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
    return Card(
      elevation: 0,
      color: context.mdSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.mdInputBorder),
      ),
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
    return Card(
      elevation: 0,
      color: context.mdSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.mdInputBorder),
      ),
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

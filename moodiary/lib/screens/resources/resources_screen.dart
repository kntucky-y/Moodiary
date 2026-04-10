import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  late Future<Map<String, dynamic>> _resourcesFuture;
  late Future<void> _locationBootstrapFuture;

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  String _selectedCategory = 'All';
  LatLng? _currentCenter;
  List<Map<String, dynamic>> _clinics = const [];
  Map<String, dynamic>? _selectedClinic;
  bool _loadingClinics = false;
  String? _clinicError;
  int _radiusMeters = 5000;

  final List<String> _categories = [
    'All',
    'Mental Health',
    'Mindfulness',
    'Wellness',
    'Social',
  ];

  final List<int> _radiusOptions = [2000, 5000, 10000, 20000];

  @override
  void initState() {
    super.initState();
    _resourcesFuture = AuthService.instance.getResources();
    _locationBootstrapFuture = _bootstrapNearbyClinics();
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

  Future<void> _filterByCategory(String category) async {
    setState(() {
      _selectedCategory = category;
      _resourcesFuture = category == 'All'
          ? AuthService.instance.getResources()
          : AuthService.instance.getResources(category: category);
    });
  }

  Widget _buildResourcesTab() {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: _categories.map((category) {
              final isSelected = _selectedCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (_) => _filterByCategory(category),
                  backgroundColor: Colors.grey[200],
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _resourcesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _resourcesFuture = AuthService.instance
                                .getResources();
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final resources = snapshot.data?['resources'] as List? ?? [];

              if (resources.isEmpty) {
                return const Center(
                  child: Text('No resources available in this category'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: resources.length,
                itemBuilder: (context, index) {
                  final resource = resources[index] as Map<String, dynamic>;
                  final isFeatured = resource['featured'] as bool? ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () {
                        _launchUrl(resource['url'] as String? ?? '');
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (isFeatured)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Featured',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Text(
                                        resource['title'] as String? ?? '',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        resource['category'] as String? ?? '',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.open_in_new, size: 20),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              resource['description'] as String? ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClinicsTab() {
    final center = _currentCenter;

    if (_clinicError != null && center == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_clinicError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _bootstrapNearbyClinics,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (center == null) {
      return FutureBuilder<void>(
        future: _locationBootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(child: Text('No location available yet.'));
        },
      );
    }

    final mapMarkers = <Marker>[
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
              setState(() {
                _selectedClinic = clinic;
              });
              _showClinicDetails(clinic);
            },
            child: Icon(
              Icons.location_pin,
              color: _selectedClinic == clinic
                  ? Theme.of(context).colorScheme.primary
                  : Colors.redAccent,
              size: 34,
            ),
          ),
        ),
      ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _loadingClinics
                      ? 'Finding nearby clinics...'
                      : '${_clinics.length} nearby clinics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Recenter',
                onPressed: _centerOnCurrentLocation,
                icon: const Icon(Icons.my_location_outlined),
              ),
              PopupMenuButton<int>(
                tooltip: 'Search radius',
                initialValue: _radiusMeters,
                onSelected: (value) {
                  setState(() {
                    _radiusMeters = value;
                  });
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
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
              height: 320,
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
                  MarkerLayer(markers: mapMarkers),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tap a marker or clinic card for details.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _clinics.isEmpty && !_loadingClinics
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No mental health clinics were found in this area. Try a larger radius or a different location.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _clinics.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final clinic = _clinics[index];
                    final selected = _selectedClinic == clinic;
                    final distance = _distanceKm(clinic);

                    return Card(
                      elevation: selected ? 3 : 1,
                      child: ListTile(
                        selected: selected,
                        leading: const Icon(Icons.local_hospital_outlined),
                        title: Text(clinic['name'] as String? ?? 'Clinic'),
                        subtitle: Text(
                          [
                                clinic['address'] as String? ?? '',
                                _formatDistance(distance),
                              ]
                              .where((value) => value.trim().isNotEmpty)
                              .join(' • '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() {
                            _selectedClinic = clinic;
                          });
                          _mapController.move(_clinicPoint(clinic), 15);
                          _showClinicDetails(clinic);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mental Health Resources'),
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.primary,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Guides'),
              Tab(text: 'Nearby Clinics'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildResourcesTab(), _buildClinicsTab()]),
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

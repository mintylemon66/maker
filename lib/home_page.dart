import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account_page.dart';
import 'device_icons.dart';
import 'services/device_service.dart';
import 'services/fall_notification_service.dart';

class HomePage extends StatefulWidget {
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  Map<String, DeviceInfo> _devices = {};
  bool _devicesLoaded = false;
  /// Latest GPS `published_at` per device (ms); used for online/offline (≤3 min = online).
  Map<String, int?> _deviceLastGpsMs = {};
  final List<StreamSubscription<FallEvent>> _fallSubscriptions = [];
  Timer? _lastGpsPollTimer;

  static const int _onlineThresholdMs = 3 * 60 * 1000;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _lastGpsPollTimer?.cancel();
    for (final sub in _fallSubscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final map = await DeviceService.getDevices(user.uid);
    if (mounted) {
      setState(() {
        _devices = map;
        _devicesLoaded = true;
      });
      _subscribeToFallAlerts();
      await _refreshLastGpsTimes();
      _startLastGpsPolling();
    }
  }

  void _startLastGpsPolling() {
    _lastGpsPollTimer?.cancel();
    _lastGpsPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _devices.isEmpty) return;
      _refreshLastGpsTimes();
    });
  }

  Future<void> _refreshLastGpsTimes() async {
    if (_devices.isEmpty) return;
    final ids = _devices.keys.toList();
    final results = await Future.wait(
      ids.map((id) async {
        final t = await DeviceService.getLastGpsUpdateTimeMs(id);
        return MapEntry(id, t);
      }),
    );
    if (!mounted) return;
    setState(() {
      _deviceLastGpsMs = Map<String, int?>.fromEntries(results);
    });
  }

  static bool _isDeviceOnline(int? lastGpsMs) {
    if (lastGpsMs == null || lastGpsMs <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch - lastGpsMs <= _onlineThresholdMs;
  }

  void _subscribeToFallAlerts() {
    for (final sub in _fallSubscriptions) {
      sub.cancel();
    }
    _fallSubscriptions.clear();
    for (final device in _devices.values) {
      final sub = DeviceService.newFallsForDeviceStream(device.deviceId).listen((fall) {
        FallNotificationService.showFallNotification(
          deviceName: device.name,
          lat: fall.lat,
          lng: fall.lng,
          timestamp: fall.timestamp,
        );
        if (mounted) {
          FallNotificationService.showFallAlertDialog(context, deviceName: device.name, fall: fall);
        }
      });
      _fallSubscriptions.add(sub);
    }
  }

  void navigateToAccountPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (builder) => AccountPage()),
    );
  }

  void _showRecentNotifications() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final alerts =
            List<RecentFallAlert>.from(FallNotificationService.recentAlerts);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Recent notifications',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child:
                      Text('No fall alerts yet.', textAlign: TextAlign.center),
                )
              else
                ...alerts.take(10).map(
                  (a) => ListTile(
                    dense: true,
                    leading:
                        const Icon(Icons.notifications_active, size: 22),
                    title: _LocationDetails(
                      lat: a.lat,
                      lng: a.lng,
                      timestamp: a.timestamp,
                    ),
                    subtitle: Text(
                      DateTime.fromMillisecondsSinceEpoch(a.timestamp)
                          .toString(),
                    ),
                    onTap: () => _showFallLocationMapDialog(
                      ctx,
                      lat: a.lat,
                      lng: a.lng,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddDeviceDialog() {
    final deviceIdController = TextEditingController();
    final nameController = TextEditingController(text: 'My device');
    var collectRealTimeLocation = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Register device'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: deviceIdController,
                  decoration: const InputDecoration(
                    labelText: 'Device ID',
                    hintText: 'From device screen or QR code',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'e.g. Grandma\'s necklace',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Collect real time location'),
                  subtitle: const Text(
                    'Turn on for a live map and directions on the Current Location tab.',
                  ),
                  value: collectRealTimeLocation,
                  onChanged: (v) => setModalState(() => collectRealTimeLocation = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final id = deviceIdController.text.trim();
                final name = nameController.text.trim().isEmpty ? 'My device' : nameController.text.trim();
                if (id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a device ID')));
                  return;
                }
                Navigator.of(ctx).pop();
                try {
                  await DeviceService.registerDevice(
                    userId: FirebaseAuth.instance.currentUser!.uid,
                    deviceId: id,
                    name: name,
                    collectRealTimeLocation: collectRealTimeLocation,
                  );
                await _loadDevices();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device registered')));
                }
              } catch (e) {
                if (mounted) {
                  final msg = e is StateError
                      ? 'Device not found. It must have reported data to the server first.'
                      : 'Failed: $e';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              }
            },
            child: const Text('Register'),
          ),
        ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: _showRecentNotifications,
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Recent notifications',
          ),
          IconButton(
            onPressed: navigateToAccountPage,
            icon: const Icon(Icons.account_circle),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text('My devices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (!_devicesLoaded)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (_devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No devices. Register a device below.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ..._devices.values.map(
                  (d) => _DeviceTile(
                    key: ValueKey(d.deviceId),
                    info: d,
                    online: HomePageState._isDeviceOnline(_deviceLastGpsMs[d.deviceId]),
                    onOpenDetail: () => _showDeviceDetailSheet(
                      context,
                      d,
                      onDeviceRemoved: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await _loadDevices();
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Device removed')),
                        );
                      },
                      onDeviceChanged: () async {
                        await _loadDevices();
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _showAddDeviceDialog,
                icon: const Icon(Icons.add),
                label: const Text('Register device'),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceInfo info;
  final bool online;
  final VoidCallback onOpenDetail;

  const _DeviceTile({
    super.key,
    required this.info,
    required this.online,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final statusColor = online ? Colors.green.shade600 : Colors.grey.shade600;
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              DeviceIconRegistry.iconFor(info.iconKey),
              size: 28,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: online ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: surface, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(info.name),
          const SizedBox(height: 2),
          Text(
            online ? 'Online' : 'Offline',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(info.deviceId),
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpenDetail,
    );
  }
}

void _showDeviceDetailSheet(
  BuildContext context,
  DeviceInfo info, {
  required Future<void> Function() onDeviceRemoved,
  Future<void> Function()? onDeviceChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height * 0.88;
      return SizedBox(
        height: h,
        child: _DeviceDetailBottomSheet(
          info: info,
          onDeviceRemoved: onDeviceRemoved,
          onDeviceChanged: onDeviceChanged,
        ),
      );
    },
  );
}

class _DeviceDetailBottomSheet extends StatefulWidget {
  final DeviceInfo info;
  final Future<void> Function() onDeviceRemoved;
  final Future<void> Function()? onDeviceChanged;

  const _DeviceDetailBottomSheet({
    required this.info,
    required this.onDeviceRemoved,
    this.onDeviceChanged,
  });

  @override
  State<_DeviceDetailBottomSheet> createState() => _DeviceDetailBottomSheetState();
}

class _DeviceDetailBottomSheetState extends State<_DeviceDetailBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _selectedIconKey;
  bool _savingIcon = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedIconKey = widget.info.iconKey;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteDevice(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          'Stop pairing "${widget.info.name}" (${widget.info.deviceId})? You can register it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await DeviceService.unregisterDevice(
        userId: user.uid,
        deviceId: widget.info.deviceId,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await widget.onDeviceRemoved();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove device: $e')),
        );
      }
    }
  }

  Future<void> _onIconChanged(String? newKey) async {
    if (newKey == null || newKey == _selectedIconKey || _savingIcon) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _savingIcon = true);
    try {
      await DeviceService.updateDeviceIconKey(
        userId: user.uid,
        deviceId: widget.info.deviceId,
        iconKey: newKey,
      );
      if (!mounted) return;
      setState(() => _selectedIconKey = newKey);
      final refresh = widget.onDeviceChanged;
      if (refresh != null) await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update icon: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingIcon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            widget.info.name,
            style: theme.textTheme.titleLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Device icon',
              border: const OutlineInputBorder(),
              suffixIcon: _savingIcon
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedIconKey,
                hint: const Text('Choose icon'),
                items: DeviceIconRegistry.sortedChoices.map((e) {
                  return DropdownMenuItem<String>(
                    value: e.key,
                    child: Row(
                      children: [
                        Icon(DeviceIconRegistry.icons[e.key]!, size: 22),
                        const SizedBox(width: 12),
                        Text(e.value),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: _savingIcon ? null : _onIconChanged,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () => _confirmDeleteDevice(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FallHistoryTab(deviceId: widget.info.deviceId, name: widget.info.name),
              _CurrentLocationTab(info: widget.info),
            ],
          ),
        ),
        Material(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Fall History'),
              Tab(text: 'Current Location'),
            ],
          ),
        ),
      ],
    );
  }
}

class _FallHistoryTab extends StatelessWidget {
  final String deviceId;
  final String name;

  const _FallHistoryTab({required this.deviceId, required this.name});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FallEvent>>(
      future: DeviceService.getFalls(deviceId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final falls = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Location is recorded only when a fall or abnormal motion is detected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (falls.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No falls recorded yet.', textAlign: TextAlign.center),
              )
            else
              ...falls.take(50).map(
                    (f) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on, size: 20),
                      title: _LocationDetails(
                        lat: f.lat,
                        lng: f.lng,
                        timestamp: f.timestamp,
                      ),
                      subtitle: Text(
                        DateTime.fromMillisecondsSinceEpoch(f.timestamp).toString(),
                      ),
                      onTap: () => _showFallLocationMapDialog(
                        context,
                        lat: f.lat,
                        lng: f.lng,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _CurrentLocationTab extends StatelessWidget {
  final DeviceInfo info;

  const _CurrentLocationTab({required this.info});

  @override
  Widget build(BuildContext context) {
    if (!info.collectRealTimeLocation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Real time location not enabled.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return StreamBuilder<DeviceLocation?>(
      stream: DeviceService.watchLastLocation(info.deviceId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final loc = snap.data;
        if (loc == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No location received yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _LiveLocationMap(lat: loc.lat, lng: loc.lng),
              ),
            ),
            const SizedBox(height: 12),
            _LocationDetails(lat: loc.lat, lng: loc.lng, timestamp: loc.updatedAt),
            const SizedBox(height: 4),
            Text(
              'Updated: ${DateTime.fromMillisecondsSinceEpoch(loc.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showFallLocationMapDialog(
                context,
                lat: loc.lat,
                lng: loc.lng,
              ),
              icon: const Icon(Icons.map),
              label: const Text('Open full map'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _openFallDirectionsInMapsApp(
                context,
                lat: loc.lat,
                lng: loc.lng,
              ),
              icon: const Icon(Icons.directions),
              label: const Text('Directions in Maps'),
            ),
          ],
        );
      },
    );
  }
}

class _LiveLocationMap extends StatefulWidget {
  final double lat;
  final double lng;

  const _LiveLocationMap({required this.lat, required this.lng});

  @override
  State<_LiveLocationMap> createState() => _LiveLocationMapState();
}

class _LiveLocationMapState extends State<_LiveLocationMap> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(covariant _LiveLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(LatLng(widget.lat, widget.lng)),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(widget.lat, widget.lng);
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: target, zoom: 16),
      onMapCreated: (c) => _controller = c,
      markers: {
        Marker(
          markerId: const MarkerId('device'),
          position: target,
          infoWindow: const InfoWindow(title: 'Device location'),
        ),
      },
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: true,
    );
  }
}

Uri _fallDirectionsUri(double lat, double lng) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return Uri.parse('http://maps.apple.com/?daddr=$lat,$lng');
  }
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$lat,$lng',
  });
}

Future<void> _openFallDirectionsInMapsApp(
  BuildContext context, {
  required double lat,
  required double lng,
}) async {
  final uri = _fallDirectionsUri(lat, lng);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open Maps')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open Maps')),
      );
    }
  }
}

void _showFallLocationMapDialog(
  BuildContext context, {
  required double lat,
  required double lng,
}) {
  final target = LatLng(lat, lng);
  final marker = {
    Marker(
      markerId: const MarkerId('fall'),
      position: target,
      infoWindow: const InfoWindow(title: 'Fall location'),
    ),
  };

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final h = MediaQuery.sizeOf(dialogContext).height * 0.5;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
              child: Row(
                children: [
                  const Icon(Icons.map, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fall location',
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: h.clamp(240.0, 520.0),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: target,
                  zoom: 16,
                ),
                markers: marker,
                zoomGesturesEnabled: true,
                scrollGesturesEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton.tonalIcon(
                onPressed: () => _openFallDirectionsInMapsApp(
                  dialogContext,
                  lat: lat,
                  lng: lng,
                ),
                icon: const Icon(Icons.directions),
                label: const Text('Directions in Maps'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _LocationDetails extends StatelessWidget {
  final double lat;
  final double lng;
  final int timestamp;

  const _LocationDetails({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  Future<String> _resolvePlace() async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return '';
      final p = placemarks.first;
      final parts = <String>[];
      if ((p.locality ?? '').isNotEmpty) parts.add(p.locality!);
      if ((p.administrativeArea ?? '').isNotEmpty) {
        parts.add(p.administrativeArea!);
      }
      if (parts.isEmpty && (p.country ?? '').isNotEmpty) {
        parts.add(p.country!);
      }
      return parts.join(', ');
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolvePlace(),
      builder: (context, snap) {
        final place = snap.data;
        if (place == null || place.isEmpty) {
          return Text(
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
        }
        return Text(place);
      },
    );
  }
}

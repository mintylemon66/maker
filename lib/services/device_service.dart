import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:placeholder/device_icons.dart';

/// Firebase Realtime Database layout (see database URL .json):
///
///   users/{userId}/devices/{deviceId}
///     name: string, addedAt: int (millis), collectRealTimeLocation: bool, iconKey: string — app registration
///
///   deviceData/{deviceId}/gps/{pushId}
///     jsonData: { latitude, longitude, fix, ... }
///     published_at: string (ISO date)
///     coreid, data, event, fw_version, public, userid
///
///   deviceData/{deviceId}/alert/{alertId}
///     event: "safety/freefall_detected" | "safety/impact_detected" | "safety/alert"
///     data: string (JSON with details, e.g. g, threshold, duration_ms)
///     published_at: string (ISO date)
///
/// Last location is read from the latest gps entry; fall events from falls/.
class DeviceService {
  static final _db = FirebaseDatabase.instance.ref();

  /// Returns true if this device ID exists in Firebase (deviceData), i.e. the device has reported data.
  static Future<bool> deviceExistsInFirebase(String deviceId) async {
    final deviceIdClean = deviceId.trim();
    if (deviceIdClean.isEmpty) return false;
    final snap = await _db.child('deviceData').child(deviceIdClean).get();
    return snap.exists;
  }

  /// Register a device to the current user. Throws if the device ID is not present in deviceData.
  static Future<void> registerDevice({
    required String userId,
    required String deviceId,
    String name = 'My device',
    bool collectRealTimeLocation = false,
  }) async {
    final deviceIdClean = deviceId.trim();
    if (deviceIdClean.isEmpty) {
      throw ArgumentError('Device ID cannot be empty');
    }
    final exists = await deviceExistsInFirebase(deviceIdClean);
    if (!exists) {
      throw StateError(
        'Device ID not found. Only devices that have reported data to the server can be registered '
        '(e.g. your 24-character Particle device ID).',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.child('users').child(userId).child('devices').child(deviceIdClean).set({
      'name': name,
      'addedAt': now,
      'collectRealTimeLocation': collectRealTimeLocation,
      'iconKey': DeviceIconRegistry.defaultKey,
    });
  }

  /// Updates the icon shown for this device in the app (`iconKey` must be a [DeviceIconRegistry] key).
  static Future<void> updateDeviceIconKey({
    required String userId,
    required String deviceId,
    required String iconKey,
  }) async {
    final raw = iconKey.trim();
    if (!DeviceIconRegistry.isValidKey(raw)) {
      throw ArgumentError('Invalid device icon key: $iconKey');
    }
    await _db.child('users').child(userId).child('devices').child(deviceId).update({
      'iconKey': raw,
    });
  }

  /// Unregister a device for this user.
  static Future<void> unregisterDevice({
    required String userId,
    required String deviceId,
  }) async {
    await _db.child('users').child(userId).child('devices').child(deviceId).remove();
  }

  /// List devices registered to this user. Returns map of deviceId -> { name, addedAt, collectRealTimeLocation }.
  static Future<Map<String, DeviceInfo>> getDevices(String userId) async {
    final snap = await _db.child('users').child(userId).child('devices').get();
    if (!snap.exists || snap.value == null) return {};
    final map = snap.value! as Map<Object?, Object?>;
    final out = <String, DeviceInfo>{};
    for (final e in map.entries) {
      final id = e.key as String;
      final data = e.value as Map<Object?, Object?>;
      out[id] = DeviceInfo(
        deviceId: id,
        name: data['name'] as String? ?? 'Device',
        addedAt: (data['addedAt'] as num?)?.toInt() ?? 0,
        collectRealTimeLocation: _coerceBool(data['collectRealTimeLocation']),
        iconKey: DeviceIconRegistry.normalizeKey(data['iconKey']),
      );
    }
    return out;
  }

  static bool _coerceBool(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  /// Latest location from deviceData/{deviceId}/gps (most recent entry).
  static Future<DeviceLocation?> getLastLocation(String deviceId) async {
    final snap = await _db.child('deviceData').child(deviceId).child('gps').orderByKey().limitToLast(1).get();
    return _parseLatestGpsMapValue(snap.value);
  }

  /// Live stream of the latest GPS point (same path as [getLastLocation]).
  static Stream<DeviceLocation?> watchLastLocation(String deviceId) {
    final q = _db.child('deviceData').child(deviceId).child('gps').orderByKey().limitToLast(1);
    return q.onValue.map((DatabaseEvent event) => _parseLatestGpsMapValue(event.snapshot.value));
  }

  static DeviceLocation? _parseLatestGpsMapValue(Object? value) {
    if (value == null) return null;
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    if (map.isEmpty) return null;
    final first = map.values.first;
    if (first is! Map) return null;
    final entry = Map<Object?, Object?>.from(first);
    final jsonData = entry['jsonData'] as Map<Object?, Object?>?;
    if (jsonData == null) return null;
    final lat = _toDouble(jsonData['latitude']);
    final lng = _toDouble(jsonData['longitude']);
    if (lat == null || lng == null) return null;
    final publishedAt = entry['published_at'] as String?;
    final updatedAt = publishedAt != null ? DateTime.tryParse(publishedAt)?.millisecondsSinceEpoch : null;
    return DeviceLocation(
      lat: lat,
      lng: lng,
      updatedAt: updatedAt ?? 0,
    );
  }

  /// Latest `published_at` on the most recent `gps` row under [deviceId], in ms since epoch.
  /// Returns null if there is no GPS row or no parseable timestamp (device never reported or unknown).
  static Future<int?> getLastGpsUpdateTimeMs(String deviceId) async {
    final snap = await _db.child('deviceData').child(deviceId).child('gps').orderByKey().limitToLast(1).get();
    if (!snap.exists || snap.value == null) return null;
    final map = snap.value! as Map<Object?, Object?>;
    if (map.isEmpty) return null;
    final entry = map.values.first as Map<Object?, Object?>;
    final publishedAt = entry['published_at'] as String?;
    if (publishedAt == null || publishedAt.isEmpty) return null;
    return DateTime.tryParse(publishedAt)?.millisecondsSinceEpoch;
  }

  static double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// List recent fall alerts for a device.
  ///
  /// We treat `event == "safety/alert"` under deviceData/{deviceId}/alert
  /// as the final "confirmed" alert, and pair it with the device's last
  /// known GPS location.
  static Future<List<FallEvent>> getFalls(String deviceId, {int limit = 50}) async {
    final alertsSnap = await _db
        .child('deviceData')
        .child(deviceId)
        .child('alert')
        .orderByKey()
        .limitToLast(limit)
        .get();
    if (!alertsSnap.exists || alertsSnap.value == null) return [];

    final loc = await getLastLocation(deviceId);
    if (loc == null) return [];

    final map = alertsSnap.value! as Map<Object?, Object?>;
    final list = <FallEvent>[];
    for (final e in map.entries) {
      final data = e.value as Map<Object?, Object?>;
      final eventType = data['event'] as String?;
      if (eventType != 'safety/alert') continue;
      final publishedAt = data['published_at'] as String?;
      if (publishedAt == null) continue;
      final ts = DateTime.tryParse(publishedAt)?.millisecondsSinceEpoch;
      if (ts == null) continue;
      list.add(FallEvent(
        fallId: e.key as String,
        lat: loc.lat,
        lng: loc.lng,
        timestamp: ts,
      ));
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// Stream of new fall alerts for a device.
  ///
  /// Listens to deviceData/{deviceId}/alert and emits only entries where
  /// event == "safety/alert", enriched with the last known GPS location.
  ///
  /// [onChildAdded] replays every existing child when the listener attaches.
  /// We load current keys with [get] first, seed [seenKeys], then ignore any
  /// replayed key so opening the screen does not notify for history.
  static Stream<FallEvent> newFallsForDeviceStream(String deviceId) {
    StreamSubscription<DatabaseEvent>? sub;
    late final StreamController<FallEvent> controller;
    controller = StreamController<FallEvent>(
      onCancel: () {
        sub?.cancel();
        sub = null;
        if (!controller.isClosed) controller.close();
      },
    );

    unawaited(Future(() async {
      try {
        final ref = _db.child('deviceData').child(deviceId).child('alert');
        final seenKeys = <String>{};

        final initial = await ref.get();
        if (initial.exists && initial.value != null) {
          _addExistingAlertKeys(initial.value, seenKeys);
        }

        if (controller.isClosed) return;

        sub = ref.onChildAdded.listen(
          (event) {
            final key = event.snapshot.key;
            if (key == null || key.isEmpty) return;
            if (seenKeys.contains(key)) return;
            seenKeys.add(key);

            final data = event.snapshot.value as Map<Object?, Object?>?;
            if (data == null) return;
            final eventType = data['event'] as String?;
            if (eventType != 'safety/alert') return;

            final publishedAt = data['published_at'] as String?;
            final ts = publishedAt != null
                ? DateTime.tryParse(publishedAt)?.millisecondsSinceEpoch
                : null;
            if (ts == null) return;

            getLastLocation(deviceId).then((loc) {
              if (loc == null || controller.isClosed) return;
              controller.add(
                FallEvent(
                  fallId: key,
                  lat: loc.lat,
                  lng: loc.lng,
                  timestamp: ts,
                ),
              );
            });
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }));

    return controller.stream;
  }

  static void _addExistingAlertKeys(Object? value, Set<String> out) {
    if (value is! Map) return;
    for (final k in value.keys) {
      if (k == null) continue;
      final s = k.toString();
      if (s.isNotEmpty) out.add(s);
    }
  }
}

class DeviceInfo {
  final String deviceId;
  final String name;
  final int addedAt;
  /// When true, the app may show live GPS in the Current Location tab.
  final bool collectRealTimeLocation;
  /// Key from [DeviceIconRegistry] for list/detail icon.
  final String iconKey;

  DeviceInfo({
    required this.deviceId,
    required this.name,
    required this.addedAt,
    this.collectRealTimeLocation = false,
    this.iconKey = DeviceIconRegistry.defaultKey,
  });
}

class DeviceLocation {
  final double lat;
  final double lng;
  final int updatedAt;

  DeviceLocation({required this.lat, required this.lng, required this.updatedAt});
}

class FallEvent {
  final String fallId;
  final double lat;
  final double lng;
  final int timestamp;

  FallEvent({required this.fallId, required this.lat, required this.lng, required this.timestamp});
}

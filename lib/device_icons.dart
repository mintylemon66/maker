import 'package:flutter/material.dart';

/// Keys stored in Firebase: `users/{uid}/devices/{deviceId}/iconKey`.
class DeviceIconRegistry {
  DeviceIconRegistry._();

  static const String defaultKey = 'watch';

  static const Map<String, IconData> icons = {
    'watch': Icons.watch,
    'favorite': Icons.favorite,
    'person': Icons.person,
    'home': Icons.home,
    'location_on': Icons.location_on,
    'health_and_safety': Icons.health_and_safety,
    'bluetooth': Icons.bluetooth,
    'smartphone': Icons.smartphone,
    'elderly': Icons.elderly,
    'sensors': Icons.sensors,
  };

  /// Human-readable labels for the device icon dropdown.
  static const Map<String, String> labels = {
    'watch': 'Watch',
    'favorite': 'Heart',
    'person': 'Person',
    'home': 'Home',
    'location_on': 'Location',
    'health_and_safety': 'Safety',
    'bluetooth': 'Bluetooth',
    'smartphone': 'Phone',
    'elderly': 'Elderly',
    'sensors': 'Sensors',
  };

  static List<MapEntry<String, String>> get sortedChoices {
    final entries = labels.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return entries;
  }

  static bool isValidKey(String key) => icons.containsKey(key);

  static IconData iconFor(String? key) {
    final k = key?.trim();
    if (k == null || k.isEmpty) return icons[defaultKey]!;
    return icons[k] ?? icons[defaultKey]!;
  }

  static String normalizeKey(Object? value) {
    if (value is! String) return defaultKey;
    final s = value.trim();
    if (s.isEmpty) return defaultKey;
    return isValidKey(s) ? s : defaultKey;
  }
}

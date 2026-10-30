import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'device_service.dart';

/// One entry for the recent fall alerts list.
class RecentFallAlert {
  final String deviceName;
  final double lat;
  final double lng;
  final int timestamp;

  RecentFallAlert({
    required this.deviceName,
    required this.lat,
    required this.lng,
    required this.timestamp,
  });
}

/// Initializes and shows fall-detection alerts (Amber Alert style).
class FallNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final List<RecentFallAlert> recentAlerts = [];
  static const int _maxRecentAlerts = 50;

  static const AndroidNotificationDetails _androidDetails = AndroidNotificationDetails(
    'fall_detection_channel',
    'Fall detection',
    channelDescription: 'Alerts when a registered device detects a fall or abnormal motion',
    importance: Importance.max,
    priority: Priority.max,
    styleInformation: BigTextStyleInformation(''),
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (_) {},
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'fall_detection_channel',
      'Fall detection',
      description: 'Alerts when a registered device detects a fall or abnormal motion',
      importance: Importance.max,
    ));
    await androidImpl?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Show a local notification for a fall (phone notification).
  static Future<void> showFallNotification({
    required String deviceName,
    required double lat,
    required double lng,
    required int timestamp,
  }) async {
    if (!_initialized) await initialize();
    _addRecent(deviceName, lat, lng, timestamp);
    await _plugin.show(
      0,
      'Fall detected',
      '$deviceName — Location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      const NotificationDetails(android: _androidDetails),
    );
  }

  static void _addRecent(String deviceName, double lat, double lng, int timestamp) {
    if (recentAlerts.isNotEmpty &&
        recentAlerts.first.timestamp == timestamp &&
        recentAlerts.first.deviceName == deviceName) return;
    recentAlerts.insert(0, RecentFallAlert(deviceName: deviceName, lat: lat, lng: lng, timestamp: timestamp));
    if (recentAlerts.length > _maxRecentAlerts) recentAlerts.removeLast();
  }

  /// Show an in-app Amber Alert style dialog. Call from a BuildContext (e.g. from navigator).
  static void showFallAlertDialog(
    BuildContext context, {
    required String deviceName,
    required FallEvent fall,
  }) {
    _addRecent(deviceName, fall.lat, fall.lng, fall.timestamp);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.amber.shade100,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 32),
            const SizedBox(width: 8),
            const Text('FALL DETECTED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: $deviceName', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Location: ${fall.lat.toStringAsFixed(5)}, ${fall.lng.toStringAsFixed(5)}'),
            const SizedBox(height: 4),
            Text('Time: ${DateTime.fromMillisecondsSinceEpoch(fall.timestamp)}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

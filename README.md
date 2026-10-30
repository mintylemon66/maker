# Placeholder Safety App

A Flutter safety companion app for wearable fall-detection devices.

The app lets users:
- create an account and sign in with Firebase Auth
- pair physical devices by device ID
- receive local fall alerts from Firebase Realtime Database events
- view fall history and map locations
- optionally enable real-time location per device
- open external turn-by-turn directions to fall/device locations

## Features

- Auth flow
  - Splash screen auto-skips login when a user session already exists.
  - Email/password sign up and login.
- Device management
  - Register device by ID (validated against `deviceData/{deviceId}` existence).
  - Optional toggle at pairing time: `Collect real time location`.
  - Delete/unpair device from user account.
  - Online/offline badge based on last GPS update (`<= 3 minutes` is online).
- Alerts
  - Local notifications for new fall events.
  - In-app fall alert dialog with location and timestamp.
  - Recent alerts list with tappable map popup.
  - Deduped stream logic to avoid replay notifications on screen open.
- Maps and location
  - Fall history entries are tappable and open an interactive map popup.
  - Current Location tab shows live location map (if enabled per device).
  - One-tap directions opens native maps app (Apple Maps on iOS, Google Maps URL otherwise).
- Account
  - Choose a profile picture from built-in presets (stored as `profileAvatarId`).
  - Light / dark / system appearance.
  - Logout and delete account.

## Tech Stack

- Flutter / Dart
- Firebase Authentication
- Firebase Realtime Database
- `flutter_local_notifications`
- `google_maps_flutter`
- `url_launcher`
- `geocoding`
- `shared_preferences` (theme mode)

## Firebase Data Model

Expected structure:

```text
users/{userId}/devices/{deviceId}
  name: string
  addedAt: int (millis)
  collectRealTimeLocation: bool
  iconKey: string (see `lib/device_icons.dart`)

users/{userId}/profileAvatarId
  string (preset id; see `lib/profile_avatar_presets.dart`)

deviceData/{deviceId}/gps/{pushId}
  jsonData: { latitude, longitude, ... }
  published_at: ISO-8601 string

deviceData/{deviceId}/alert/{alertId}
  event: "safety/alert" (plus other safety event types)
  data: json string payload
  published_at: ISO-8601 string
```

Notes:
- The app currently treats `event == "safety/alert"` as the final/confirmed alert.
- Fall history uses recent alerts plus the latest known GPS location.

## Prerequisites

- Flutter SDK installed
- Xcode (for iOS builds)
- Android Studio / Android SDK (for Android builds)
- A Firebase project configured for Android and iOS
- Google Maps Platform API key(s)

## Setup

### 1) Install dependencies

```bash
flutter pub get
```

### 2) Firebase configuration

Firebase keys and platform config files are not included in this copy. Create your own Firebase project, then generate them:
- `lib/firebase_options.dart`
- Android `google-services.json`
- iOS `GoogleService-Info.plist`

If you need to regenerate, use FlutterFire CLI:

```bash
flutterfire configure
```

### 3) Google Maps keys

Enable in Google Cloud:
- Maps SDK for Android
- Maps SDK for iOS

Then configure keys:
- Android: add `com.google.android.geo.API_KEY` in `android/app/src/main/AndroidManifest.xml`
- iOS: call `GMSServices.provideAPIKey(...)` in `ios/Runner/AppDelegate.swift`

Security best practice:
- Restrict keys by application (package/bundle) and by API.
- Rotate keys if they were ever shared publicly.

### 4) iOS pods

```bash
cd ios
pod install
cd ..
```

## Run

```bash
flutter run
```

Useful checks:

```bash
flutter analyze
flutter test
```

## Hardware / Firmware

Firmware lives in:
- `hardware_code/necklace_code.ino`

It publishes GPS and safety events expected by the app's Realtime Database readers.

## Suggested Roadmap

- Push notifications via FCM for background/terminated delivery
- Caregiver contacts and multi-recipient alert fanout
- Device battery/health telemetry and stale-device warnings
- Geofencing and safe-zone notifications
- Fall confirmation workflow (`I'm okay` timer/escalation)
- Incident timeline export (CSV/PDF)

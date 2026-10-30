import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'app_theme_mode';

final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadSavedThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final s = prefs.getString(_prefKey);
  appThemeModeNotifier.value = switch (s) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

Future<void> setAppThemeMode(ThemeMode mode) async {
  appThemeModeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _prefKey,
    switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    },
  );
}

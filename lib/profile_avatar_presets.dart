import 'package:flutter/material.dart';

/// Built-in profile avatars (no uploads). Stored in RTDB as `users/{uid}/profileAvatarId`.
class ProfileAvatarPreset {
  final String id;
  final String label;
  final IconData icon;
  final List<Color> gradientLight;
  final List<Color> gradientDark;

  const ProfileAvatarPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.gradientLight,
    required this.gradientDark,
  });
}

const String kDefaultProfileAvatarId = 'sage';

const List<ProfileAvatarPreset> kProfileAvatarPresets = [
  ProfileAvatarPreset(
    id: 'sage',
    label: 'Sage',
    icon: Icons.eco,
    gradientLight: [Color(0xFF97DE62), Color(0xFF5CAD2E)],
    gradientDark: [Color(0xFF6FA344), Color(0xFF2F5A1A)],
  ),
  ProfileAvatarPreset(
    id: 'ocean',
    label: 'Ocean',
    icon: Icons.water_drop,
    gradientLight: [Color(0xFF4FC3F7), Color(0xFF0288D1)],
    gradientDark: [Color(0xFF29B6F6), Color(0xFF01579B)],
  ),
  ProfileAvatarPreset(
    id: 'sunset',
    label: 'Sunset',
    icon: Icons.wb_sunny,
    gradientLight: [Color(0xFFFFB74D), Color(0xFFF57C00)],
    gradientDark: [Color(0xFFFF9800), Color(0xFFE65100)],
  ),
  ProfileAvatarPreset(
    id: 'bloom',
    label: 'Bloom',
    icon: Icons.local_florist,
    gradientLight: [Color(0xFFF48FB1), Color(0xFFC2185B)],
    gradientDark: [Color(0xFFEC407A), Color(0xFF880E4F)],
  ),
  ProfileAvatarPreset(
    id: 'shield',
    label: 'Shield',
    icon: Icons.health_and_safety,
    gradientLight: [Color(0xFF80CBC4), Color(0xFF00897B)],
    gradientDark: [Color(0xFF4DB6AC), Color(0xFF00695C)],
  ),
  ProfileAvatarPreset(
    id: 'night',
    label: 'Night',
    icon: Icons.nightlight_round,
    gradientLight: [Color(0xFF9FA8DA), Color(0xFF3949AB)],
    gradientDark: [Color(0xFF7986CB), Color(0xFF283593)],
  ),
  ProfileAvatarPreset(
    id: 'spark',
    label: 'Spark',
    icon: Icons.bolt,
    gradientLight: [Color(0xFFFFF176), Color(0xFFF9A825)],
    gradientDark: [Color(0xFFFFEE58), Color(0xFFF57F17)],
  ),
  ProfileAvatarPreset(
    id: 'heart',
    label: 'Heart',
    icon: Icons.favorite,
    gradientLight: [Color(0xFFEF9A9A), Color(0xFFE53935)],
    gradientDark: [Color(0xFFE57373), Color(0xFFC62828)],
  ),
];

ProfileAvatarPreset profileAvatarPresetFor(String? id) {
  if (id == null || id.isEmpty) {
    return kProfileAvatarPresets.firstWhere((p) => p.id == kDefaultProfileAvatarId);
  }
  for (final p in kProfileAvatarPresets) {
    if (p.id == id) return p;
  }
  return kProfileAvatarPresets.firstWhere((p) => p.id == kDefaultProfileAvatarId);
}

bool isValidProfileAvatarId(String id) =>
    kProfileAvatarPresets.any((p) => p.id == id);

/// Circular gradient avatar with icon; adapts to light/dark [Brightness].
class ProfileAvatarDisplay extends StatelessWidget {
  final String avatarId;
  final double size;

  const ProfileAvatarDisplay({
    super.key,
    required this.avatarId,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final preset = profileAvatarPresetFor(avatarId);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = dark ? preset.gradientDark : preset.gradientLight;
    return Semantics(
      label: 'Profile avatar, ${preset.label}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          preset.icon,
          size: size * 0.45,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'login_page.dart';
import 'profile_avatar_presets.dart';
import 'theme_settings.dart';

class AccountPage extends StatefulWidget {
  @override
  AccountPageState createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController passwordController = TextEditingController();

  bool submitLock = false;

  String _avatarId = kDefaultProfileAvatarId;
  bool _savingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfileAvatar();
  }

  Future<void> _loadProfileAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('profileAvatarId')
        .get();
    if (!mounted) return;
    if (snap.exists && snap.value is String) {
      final id = (snap.value as String).trim();
      if (isValidProfileAvatarId(id)) {
        setState(() => _avatarId = id);
        return;
      }
    }
    setState(() => _avatarId = kDefaultProfileAvatarId);
  }

  Future<void> _selectAvatar(String id) async {
    if (!isValidProfileAvatarId(id) || id == _avatarId || _savingAvatar) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _savingAvatar = true);
    try {
      final ref = FirebaseDatabase.instance.ref().child('users').child(user.uid);
      await ref.child('profileAvatarId').set(id);
      await ref.child('profilePhotoUrl').remove();
      if (mounted) setState(() => _avatarId = id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save avatar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (builder) => LoginPage()),
      (route) => false,
    );
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return "Please enter your password";
    }
    return null;
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: "Dismiss",
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void submitDeleteForm() async {
    if (submitLock) return;
    submitLock = true;

    if (formKey.currentState!.validate()) {
      try {
        final user = FirebaseAuth.instance.currentUser!;
        final email = user.email!;
        final password = passwordController.text;
        final credential =
            EmailAuthProvider.credential(email: email, password: password);

        final userCred = await user.reauthenticateWithCredential(credential);

        await userCred.user!.delete();
        await logout();
      } catch (e) {
        showSnackBar("An Error Has Occured");
      }
    }
    submitLock = false;
  }

  void showDeleteAlert() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Account"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Are you sure you want to delete your account? This action cannot be undone.",
                ),
                const SizedBox(height: 12),
                const Text(
                  "Please enter your password to confirm the deletion of your account.",
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 20, right: 10, left: 10),
                  child: TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    validator: validatePassword,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: "Password",
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      prefixIcon: Icon(
                        Icons.lock,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 10.0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.close),
              label: const Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () {
                submitDeleteForm();
              },
              child: const Text("Delete Account"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Account"),
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface,
              cs.surfaceContainerHighest.withValues(alpha: 0.5),
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 32.0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ProfileAvatarDisplay(avatarId: _avatarId, size: 120),
                          if (_savingAvatar)
                            const SizedBox(
                              width: 120,
                              height: 120,
                              child: Center(
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choose a profile picture',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pick one of the presets below.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: kProfileAvatarPresets.map((p) {
                          final selected = p.id == _avatarId;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _savingAvatar ? null : () => _selectAvatar(p.id),
                              customBorder: const CircleBorder(),
                              child: Ink(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? cs.primary
                                        : cs.outlineVariant,
                                    width: selected ? 3 : 1,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: ProfileAvatarDisplay(
                                    avatarId: p.id,
                                    size: 52,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: appThemeModeNotifier,
                        builder: (context, mode, _) {
                          return SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.system,
                                label: Text('System'),
                                icon: Icon(Icons.brightness_auto, size: 18),
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.light,
                                label: Text('Light'),
                                icon: Icon(Icons.light_mode, size: 18),
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.dark,
                                label: Text('Dark'),
                                icon: Icon(Icons.dark_mode, size: 18),
                              ),
                            ],
                            selected: {mode},
                            onSelectionChanged: (s) {
                              if (s.isNotEmpty) setAppThemeMode(s.first);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Email",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Flexible(
                            child: Text(
                              FirebaseAuth.instance.currentUser!.email ?? '',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: logout,
                          child: const Text("Log Out"),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.error,
                            foregroundColor: cs.onError,
                          ),
                          onPressed: showDeleteAlert,
                          child: const Text("Delete Account"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

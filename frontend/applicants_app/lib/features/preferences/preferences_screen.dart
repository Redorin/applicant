import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/notifications_pref_provider.dart';
import '../../shared/widgets/page_header.dart';
import '../auth/auth_provider.dart';
import '../master_data/widgets/form_bits.dart';
import '../shell/toast_provider.dart';

/// Splits the account's single free-text `full_name` column into First/Last
/// for editing — everything before the LAST space is "first", the last
/// token is "last" (so "Lourdes C. Samson" → "Lourdes C." / "Samson").
(String, String) _splitName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return ('', '');
  final lastSpace = trimmed.lastIndexOf(' ');
  if (lastSpace == -1) return (trimmed, '');
  return (trimmed.substring(0, lastSpace), trimmed.substring(lastSpace + 1));
}

class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _passwordError;
  bool _savingProfile = false;
  bool _changingPassword = false;
  File? _profilePhoto;

  @override
  void initState() {
    super.initState();
    final (first, last) = _splitName(ref.read(authProvider).fullName ?? '');
    _firstName = TextEditingController(text: first);
    _lastName = TextEditingController(text: last);
    _loadProfilePhoto();
  }

  static const _photoPathKey = 'profile_photo_path';

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_photoPathKey);
    if (path != null && File(path).existsSync()) {
      setState(() => _profilePhoto = File(path));
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _cancelNameEdit() {
    final (first, last) = _splitName(ref.read(authProvider).fullName ?? '');
    setState(() {
      _firstName.text = first;
      _lastName.text = last;
    });
  }

  Future<void> _pickProfilePhoto() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png'],
        ),
      ],
    );
    if (file != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_photoPathKey, file.path);
      setState(() => _profilePhoto = File(file.path));
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _savingProfile = true);
    final ok = await ref
        .read(authProvider.notifier)
        .updateProfile(_firstName.text.trim(), _lastName.text.trim());
    if (!mounted) return;
    setState(() => _savingProfile = false);
    if (ok) {
      ref.read(toastProvider.notifier).show('Settings saved successfully');
    }
  }

  Future<void> _submitPasswordChange() async {
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _passwordError = 'New password and confirmation do not match.');
      return;
    }
    if (_newPassword.text.trim().length < 6) {
      setState(() => _passwordError = 'New password must be at least 6 characters.');
      return;
    }
    setState(() {
      _passwordError = null;
      _changingPassword = true;
    });
    final ok = await ref
        .read(authProvider.notifier)
        .changePassword(_currentPassword.text, _newPassword.text);
    if (!mounted) return;
    setState(() => _changingPassword = false);
    if (ok) {
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      ref.read(toastProvider.notifier).show('Password changed successfully');
    } else {
      setState(() =>
          _passwordError = ref.read(authProvider).error ?? 'Could not change password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);

    final name = (auth.fullName ?? '').trim();
    final (first, last) = _splitName(name);
    final initials = [first, last]
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: PageHeader(title: 'Preferences')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.selectionSoft,
                  borderRadius: AppRadius.smAll,
                ),
                child: const Text('v3.0.0',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Profile card (left) ──
                SizedBox(
                  width: 300,
                  child: _ProfileCard(
                    initials: initials,
                    fullName: name,
                    username: auth.username,
                    profilePhoto: _profilePhoto,
                    onEditPhoto: _pickProfilePhoto,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxl),
                // ── Settings panels (right) ──
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Personal Information
                        _SettingsCard(
                          icon: Icons.person_outline,
                          iconBackground: AppColors.infoBack,
                          iconColor: AppColors.infoInk,
                          title: 'Personal Information',
                          subtitle: 'Update your name and profile details',
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Labeled(
                                      label: 'First Name',
                                      child: TextField(
                                          controller: _firstName,
                                          style: kValueStyle,
                                          decoration: kInputDecoration),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Labeled(
                                      label: 'Last Name',
                                      child: TextField(
                                          controller: _lastName,
                                          style: kValueStyle,
                                          decoration: kInputDecoration),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: _savingProfile ? null : _cancelNameEdit,
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _savingProfile ? null : _saveProfile,
                                    child: Text(_savingProfile ? 'Saving…' : 'Save Changes'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // Password & Security
                        _SettingsCard(
                          icon: Icons.lock_outline,
                          iconBackground: AppColors.warnBack,
                          iconColor: AppColors.warnInk,
                          title: 'Password & Security',
                          subtitle: 'Manage your password and security settings',
                          child: Column(
                            children: [
                              Labeled(
                                label: 'Current Password',
                                child: TextField(
                                    controller: _currentPassword,
                                    obscureText: true,
                                    style: kValueStyle,
                                    decoration: kInputDecoration),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Labeled(
                                      label: 'New Password',
                                      child: TextField(
                                          controller: _newPassword,
                                          obscureText: true,
                                          style: kValueStyle,
                                          decoration: kInputDecoration),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Labeled(
                                      label: 'Confirm Password',
                                      child: TextField(
                                          controller: _confirmPassword,
                                          obscureText: true,
                                          style: kValueStyle,
                                          decoration: kInputDecoration),
                                    ),
                                  ),
                                ],
                              ),
                              if (_passwordError != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerSoft,
                                    border:
                                        Border.all(color: AppColors.danger.withValues(alpha: .35)),
                                    borderRadius: AppRadius.smAll,
                                  ),
                                  child: Text(_passwordError!,
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton(
                                    onPressed:
                                        _changingPassword ? null : _submitPasswordChange,
                                    child: Text(
                                        _changingPassword ? 'Changing…' : 'Change Password'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // Notifications
                        _SettingsCard(
                          icon: Icons.notifications_outlined,
                          iconBackground: AppColors.okBack,
                          iconColor: AppColors.okInk,
                          title: 'Notifications',
                          subtitle: 'Configure your notification preferences',
                          child: _ToggleRow(
                            label: 'Follow-up Alerts',
                            description:
                                'Show the bell badge and panel for applications '
                                'with no follow-up in 30+ days.',
                            value: notificationsEnabled,
                            onChanged: (v) =>
                                ref.read(notificationsEnabledProvider.notifier).set(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: iconBackground, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          child,
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.initials,
    required this.fullName,
    required this.username,
    required this.profilePhoto,
    required this.onEditPhoto,
  });
  final String initials;
  final String fullName;
  final String? username;
  final File? profilePhoto;
  final VoidCallback onEditPhoto;

  @override
  Widget build(BuildContext context) {
    Widget infoRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink)),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.actionBlue,
            backgroundImage: profilePhoto != null ? FileImage(profilePhoto!) : null,
            child: profilePhoto != null
                ? null
                : Text(initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          Text(fullName.isEmpty ? '—' : fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('@${username ?? '—'}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: AppSpacing.xl),
          Container(width: double.infinity, height: 1, color: AppColors.line),
          const SizedBox(height: AppSpacing.lg),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('ACCOUNT DETAILS',
                style: AppTypography.fieldLabel),
          ),
          const SizedBox(height: AppSpacing.sm),
          infoRow('Role', 'Staff'),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEditPhoto,
              icon: const Icon(Icons.camera_alt_outlined, size: 14),
              label: const Text('Edit Profile Photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.actionBlue,
                side: const BorderSide(color: AppColors.line),
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(description,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? AppColors.actionBlue : AppColors.line,
              borderRadius: BorderRadius.circular(11),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .15),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

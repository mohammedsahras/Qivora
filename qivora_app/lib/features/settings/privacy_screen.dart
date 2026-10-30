import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants.dart';

/// Privacy controls persisted locally via SharedPreferences.
///
/// NOTE: These controls affect only this device. Qivora stores messages
/// locally and has no messaging backend, so there is no remote party whose
/// behavior these settings could enforce. They are documented here as
/// local preferences; once a signaling server/backend is connected, the
/// stored values can be wired to the actual privacy enforcement.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _readReceipts = true;
  bool _lastSeen = true;
  bool _profilePhotoVisible = true;

  static const _kReadReceipts = 'privacy_read_receipts';
  static const _kLastSeen = 'privacy_last_seen';
  static const _kProfilePhotoVisible = 'privacy_profile_photo_visible';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _readReceipts = prefs.getBool(_kReadReceipts) ?? true;
      _lastSeen = prefs.getBool(_kLastSeen) ?? true;
      _profilePhotoVisible = prefs.getBool(_kProfilePhotoVisible) ?? true;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.secondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          _sectionTitle('Read receipts'),
          _tile(
            icon: Icons.check_circle_outline,
            title: 'Read receipts',
            subtitle: 'Show delivery and read status on messages you send.',
            value: _readReceipts,
            onChanged: (v) {
              setState(() => _readReceipts = v);
              _save(_kReadReceipts, v);
            },
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.access_time,
            title: 'Last seen',
            subtitle: 'Show when you were last active.',
            value: _lastSeen,
            onChanged: (v) {
              setState(() => _lastSeen = v);
              _save(_kLastSeen, v);
            },
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.person_outline,
            title: 'Profile photo visibility',
            subtitle: 'Show your profile photo to contacts.',
            value: _profilePhotoVisible,
            onChanged: (v) {
              setState(() => _profilePhotoVisible = v);
              _save(_kProfilePhotoVisible, v);
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              QivoraConstants.localOnlyNote,
              style: TextStyle(
                color:
                    isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF94A3B8)
              : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

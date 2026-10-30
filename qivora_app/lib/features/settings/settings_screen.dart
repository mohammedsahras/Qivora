import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../core/database/database_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/qivora_avatar.dart';
import '../../core/constants.dart';
import 'privacy_screen.dart';

/// Theme mode provider backed by SharedPreferences.
///
/// QivoraApp watches this provider so light/dark/system selection from
/// Settings is applied to the whole app immediately and persisted across
/// restarts.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('theme_mode_index') ?? 0;
    state = ThemeMode.values[idx.clamp(0, ThemeMode.values.length - 1)];
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode_index', mode.index);
  }
}

/// Settings and profile screen.
///
/// Profile photo/display name/about are persisted in SharedPreferences and
/// the local SQLite users table. Theme is persisted and applied app-wide via
/// [themeModeProvider].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _displayName = 'Qivora User';
  String _about = 'Hey there! I am using Qivora.';
  bool _notifications = true;
  String? _avatarPath;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final db = await DatabaseService.instance.database;
    final id = prefs.getString('user_id');
    if (!mounted) return;
    setState(() {
      _displayName = prefs.getString('display_name') ?? _displayName;
      _about = prefs.getString('about') ?? _about;
      _notifications = prefs.getBool('notifications') ?? true;
      _avatarPath = prefs.getString('avatar_path');
      _userId = id ?? _userId;
    });
    // Keep the users table row in sync with the profile preferences.
    if (id != null && id.isNotEmpty) {
      await db.update(
        'users',
        {
          'display_name': _displayName,
          'about': _about,
          'avatar_path': _avatarPath,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _saveString(String key, String value, {String? column}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    if (column != null && _userId != null) {
      final db = await DatabaseService.instance.database;
      await db.update(
        'users',
        {column: value, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [_userId],
      );
    }
  }

  Future<void> _editProfileField({
    required String title,
    required String currentValue,
    required String key,
    String? column,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: title.contains('name') ? 1 : 4,
          decoration: InputDecoration(hintText: currentValue),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      if (key == 'display_name') _displayName = result;
      if (key == 'about') _about = result;
    });
    await _saveString(key, result, column: column);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    }
  }

  Future<void> _changeProfilePhoto() async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1024,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not pick photo: ${e.message ?? e}'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not pick photo: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (picked == null) return; // user cancelled
    try {
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/Qivora/avatars');
      if (!await avatarDir.exists()) await avatarDir.create(recursive: true);
      final name = '${const Uuid().v4()}${p.extension(picked.path)}';
      await picked.saveTo('${avatarDir.path}/$name');
      setState(() => _avatarPath = '${avatarDir.path}/$name');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_path', '${avatarDir.path}/$name');
      await _saveString('avatar_path', '${avatarDir.path}/$name',
          column: 'avatar_path');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save photo: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Log out of your Qivora account? Your local chat history is kept '
          'on this device, but you will need to set up your profile again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    if (mounted) context.go('/login');
  }

  Future<void> _showStorageDialog() async {
    final db = await DatabaseService.instance.database;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = await _databasePath();
    final dbFile = File(dbPath);
    final dbSize = dbFile.existsSync() ? dbFile.lengthSync() : 0;

    final attachDir = Directory('${dir.path}/Qivora/attachments');
    int attachSize = 0;
    int attachCount = 0;
    if (await attachDir.exists()) {
      await for (final entity in attachDir.list(recursive: true)) {
        if (entity is File) {
          attachSize += await entity.length();
          attachCount += 1;
        }
      }
    }

    final msgCount = _intFromRow((await db.rawQuery(
                'SELECT COUNT(*) AS c FROM messages WHERE deleted_at IS NULL'))
            .first) ??
        0;
    final convCount = _intFromRow(
            (await db.rawQuery('SELECT COUNT(*) AS c FROM conversations'))
                .first) ??
        0;
    final attachmentsSummary =
        '${_formatBytes(attachSize)} ($attachCount files)';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage usage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _storageRow('Database', _formatBytes(dbSize)),
            _storageRow('Messages', '$msgCount'),
            _storageRow('Conversations', '$convCount'),
            _storageRow('Attachments', attachmentsSummary),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _exportBackup(dbPath, dir);
            },
            child: const Text('Export backup'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(String dbPath, Directory dir) async {
    final backupDir = Directory('${dir.path}/Qivora/backups');
    if (!await backupDir.exists()) await backupDir.create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '${backupDir.path}/qivora_backup_$timestamp.db';
    await File(dbPath).copy(backupPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Database exported to $backupPath'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<String> _databasePath() async {
    final db = await DatabaseService.instance.database;
    return db.path;
  }

  static int? _intFromRow(Map<String, dynamic> row) {
    final v = row.values.first;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: QivoraConstants.appName,
      applicationVersion: QivoraConstants.appVersion,
      applicationIcon: const Icon(Icons.chat_bubble_rounded,
          color: AppColors.primary, size: 40),
      children: [
        const Text(
          QivoraConstants.tagline,
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help center'),
        content: const Text(
          'Qivora is a local-first messaging app. Messages and conversations '
          'are stored in an on-device SQLite database.\n\n'
          '• Start a conversation from Contacts or Chats.\n'
          '• Long-press a conversation to pin, mute, archive, or delete it.\n'
          '• Long-press a message to copy, reply, edit, forward, or delete it.\n'
          '• Attach photos and files from the message input.\n'
          '• Voice/video calls require a signaling server and are not available '
          'in this local build.\n\n'
          'Theme and profile preferences are saved locally and persist across '
          'restarts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _storageRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAvatar = _avatarPath != null &&
        _avatarPath!.isNotEmpty &&
        File(_avatarPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          // Profile section
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _changeProfilePhoto,
                  child: QivoraAvatar(
                    displayName: _displayName,
                    radius: 40,
                    imageProvider:
                        hasAvatar ? FileImage(File(_avatarPath!)) : null,
                    online: false,
                    showOnlineIndicator: false,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _about,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editProfileField(
                          title: 'Edit display name',
                          currentValue: _displayName,
                          key: 'display_name',
                          column: 'display_name',
                        ),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Edit name'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _changeProfilePhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Change photo'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Account
          _sectionTitle('Account'),
          _tile(
            context,
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'Edit your profile information',
            onTap: () => _editProfileField(
              title: 'Edit about',
              currentValue: _about,
              key: 'about',
              column: 'about',
            ),
          ),
          _tile(
            context,
            icon: Icons.lock_outline,
            title: 'Privacy',
            subtitle: 'Manage your privacy settings',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PrivacyScreen(),
            )),
          ),
          _tile(
            context,
            icon: Icons.logout,
            title: 'Logout',
            subtitle: 'Sign out of your account',
            onTap: _logout,
            titleColor: AppColors.error,
            iconColor: AppColors.error,
          ),
          const Divider(height: 1),
          // Notifications
          _sectionTitle('Notifications'),
          SwitchListTile(
            title: const Text('Message notifications'),
            subtitle: const Text('Receive notifications for new messages'),
            value: _notifications,
            onChanged: (v) async {
              setState(() => _notifications = v);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('notifications', v);
            },
            activeThumbColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          const Divider(height: 1),
          // Appearance
          _sectionTitle('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(
              _themeLabel(themeMode),
              style: TextStyle(
                color:
                    isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
              ),
            ),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text('System')),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await ref.read(themeModeProvider.notifier).set(v);
                }
              },
            ),
          ),
          const Divider(height: 1),
          // Storage & Data
          _sectionTitle('Storage & Data'),
          _tile(
            context,
            icon: Icons.storage_outlined,
            title: 'Storage usage',
            subtitle: 'Manage downloads and cache',
            onTap: _showStorageDialog,
          ),
          _tile(
            context,
            icon: Icons.backup_outlined,
            title: 'Chat backup',
            subtitle: 'Export a copy of your local chat database',
            onTap: () async {
              final db = await DatabaseService.instance.database;
              final dir = await getApplicationDocumentsDirectory();
              await _exportBackup(db.path, dir);
            },
          ),
          const Divider(height: 1),
          // App info
          _sectionTitle('App'),
          _tile(
            context,
            icon: Icons.info_outline,
            title: 'About Qivora',
            subtitle: 'Version ${QivoraConstants.appVersion}',
            onTap: _showAbout,
          ),
          _tile(
            context,
            icon: Icons.help_outline,
            title: 'Help center',
            subtitle: 'Get help and support',
            onTap: _showHelp,
          ),
          const SizedBox(height: 24),
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

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
    Color? iconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.secondary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? (isDark ? Colors.white : AppColors.textMain),
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppColors.secondary,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }
}

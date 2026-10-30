import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database_service.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/qivora_avatar.dart';
import '../../core/widgets/qivora_empty_state.dart';

/// Contacts screen — browse local users, add contacts, and start a
/// conversation. Contacts are stored in the local SQLite database only;
/// Qivora does not read the device's phone book, so no contact permission
/// is required and no private contact information is exposed.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> _users = [];
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  String _ownerUserId = 'me';

  @override
  void initState() {
    super.initState();
    _loadOwnerId();
    _load();
  }

  Future<void> _loadOwnerId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ownerUserId = prefs.getString('user_id') ?? 'me';
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await DatabaseService.instance.database;
      final users = await db.query('users');
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load contacts.';
        });
      }
    }
  }

  Future<void> _retry() => _load();

  Future<void> _addContact(String userId) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'contacts',
      {
        'id': const Uuid().v4(),
        'owner_user_id': _ownerUserId,
        'contact_user_id': userId,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact added'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _openOrCreateChat(Map<String, dynamic> u) async {
    final router = GoRouter.of(context);
    final displayName = u['display_name'] as String? ?? 'Unknown';
    final db = await DatabaseService.instance.database;

    // Reuse an existing direct conversation with this contact if one exists.
    final existing = await db.query(
      'conversations',
      where: 'title = ? AND type = ?',
      whereArgs: [displayName, 'direct'],
    );

    String cid;
    if (existing.isNotEmpty) {
      cid = existing.first['id'] as String;
    } else {
      cid = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      await db.insert(
        'conversations',
        {
          'id': cid,
          'title': displayName,
          'type': 'direct',
          'created_at': now,
          'updated_at': now,
        },
      );
      // Track both users in the conversation so pin/mute/unread state is
      // stored per participant.
      await db.insert(
        'conversation_participants',
        {
          'id': const Uuid().v4(),
          'conversation_id': cid,
          'user_id': _ownerUserId,
          'role': 'member',
          'joined_at': now,
          'is_muted': 0,
          'is_pinned': 0,
          'unread_count': 0,
        },
      );
      await db.insert(
        'conversation_participants',
        {
          'id': const Uuid().v4(),
          'conversation_id': cid,
          'user_id': u['id'] as String? ?? '',
          'role': 'member',
          'joined_at': now,
          'is_muted': 0,
          'is_pinned': 0,
          'unread_count': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    router.go('/chat/$cid?title=${Uri.encodeComponent(displayName)}');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = _search.text.toLowerCase();
    final filtered = _users
        .where((u) =>
            (u['display_name'] as String? ?? '').toLowerCase().contains(q))
        .toList();

    Widget body;
    if (_loading) {
      body = const Center(
        child: QivoraLoading(message: 'Loading contacts…'),
      );
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load contacts',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _retry, child: const Text('Retry')),
          ],
        ),
      );
    } else if (filtered.isEmpty) {
      body = QivoraEmptyState(
        icon: _search.text.isNotEmpty ? Icons.search_off : Icons.person_off,
        title:
            _search.text.isNotEmpty ? 'No contacts found' : 'No contacts yet',
        subtitle: _search.text.isNotEmpty
            ? 'Try adjusting your search'
            : 'Add a contact to start messaging.',
        action: null,
      );
    } else {
      body = Expanded(
        child: ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final u = filtered[i];
            final displayName = u['display_name'] as String? ?? 'Unknown';
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: QivoraAvatar(
                displayName: displayName,
                radius: 26,
                online: false,
                showOnlineIndicator: false,
              ),
              title: Text(
                displayName,
                style: TextStyle(
                  color: isDark ? Colors.white : AppColors.textMain,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                u['username'] as String? ?? '',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.person_add, size: 20),
                onPressed: () => _addContact(u['id'] as String),
                tooltip: 'Add contact',
              ),
              onTap: () => _openOrCreateChat(u),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search contacts',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        tooltip: 'Clear search',
                      )
                    : null,
                filled: true,
                fillColor: isDark ? AppColors.darkSurface : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          body,
        ],
      ),
    );
  }
}

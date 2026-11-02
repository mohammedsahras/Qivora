import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database_service.dart';

/// Group list + creation using existing conversations/participants tables.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.title, c.avatar_path, COUNT(p.id) AS members
      FROM conversations c
      LEFT JOIN conversation_participants p ON p.conversation_id = c.id
      WHERE c.type = 'group'
      GROUP BY c.id
      ORDER BY c.updated_at DESC
    ''');
    if (!mounted) return;
    setState(() => _groups = rows);
  }

  Future<void> _createGroup() async {
    final db = await DatabaseService.instance.database;
    final nameCtl = TextEditingController();
    final users = await db.query('users');
    final selected = <String>{};
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('New Group'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Group name')),
                ...users.map((u) => CheckboxListTile(
                      value: selected.contains(u['id']),
                      onChanged: (v) => setDlg(() => v == true ? selected.add(u['id'] as String) : selected.remove(u['id'])),
                      title: Text((u['display_name'] as String?) ?? u['id'].toString()),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty || selected.isEmpty) return;
                final now = DateTime.now().toIso8601String();
                final gid = const Uuid().v4();
                await db.insert('conversations', {'id': gid, 'title': name, 'type': 'group', 'created_at': now, 'updated_at': now});
                await db.insert('conversation_participants', {'id': 'p_$gid', 'conversation_id': gid, 'user_id': 'me', 'role': 'owner', 'joined_at': now, 'is_muted': 0, 'is_pinned': 0, 'unread_count': 0});
                await db.update('conversations', {'owner_user_id': 'me'}, where: 'id = ?', whereArgs: [gid]);
                for (final uid in selected) {
                  try {
                    await db.insert('conversation_participants', {'id': 'p_${gid}_$uid', 'conversation_id': gid, 'user_id': uid, 'role': 'member', 'joined_at': now, 'is_muted': 0, 'is_pinned': 0, 'unread_count': 0});
                  } catch (_) {}
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton(onPressed: _createGroup, child: const Icon(Icons.add)),
      body: _groups.isEmpty
          ? const Center(child: Text('No groups yet'))
          : ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (_, i) {
                final g = _groups[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: g['avatar_path'] != null
                        ? FileImage(File(g['avatar_path'] as String))
                        : null,
                    child: g['avatar_path'] != null ? null : const Icon(Icons.group),
                  ),
                  title: Text(g['title'] as String),
                  subtitle: Text('${g['members']} members'),
                  onTap: () => context.push('/groups/detail/${g['id']}'),
                );
              },
            ),
    );
  }
}

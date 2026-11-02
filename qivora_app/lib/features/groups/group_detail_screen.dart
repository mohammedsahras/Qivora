import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import '../../core/database/database_service.dart';
import '../../core/widgets/qivora_back_button.dart';
import 'group_service.dart';

/// Group details with member management using existing participants table.
class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});
  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _members = [];
  String _uid = 'me';

  String? get _ownerId => _group?['owner_user_id'] as String?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id') ?? 'me';
    final db = await DatabaseService.instance.database;
    final g = await db.query('conversations', where: 'id = ? AND type = ?', whereArgs: [widget.groupId, 'group']);
    final m = await db.rawQuery('''
      SELECT p.id, p.user_id, p.role, u.display_name
      FROM conversation_participants p
      LEFT JOIN users u ON u.id = p.user_id
      WHERE p.conversation_id = ?
      ORDER BY p.role DESC, p.user_id
    ''', [widget.groupId]);
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _group = g.isEmpty ? null : g.first;
      _members = m;
    });
  }

  bool get _isAdmin => _members.any((m) => m['user_id'] == _uid && (m['role'] == 'admin' || m['role'] == 'owner'));

  bool get _isOwner => _ownerId == _uid;

  Future<void> _addMember() async {
    final db = await DatabaseService.instance.database;
    final users = await db.query('users');
    if (!mounted) return;
    await showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Add member'),
      content: SizedBox(width: double.maxFinite, height: 250, child: ListView(
        children: users.where((u) => !_members.any((m) => m['user_id'] == u['id'])).map((u) => ListTile(
          title: Text((u['display_name'] as String?) ?? u['id'].toString()),
          onTap: () async {
            final now = DateTime.now().toIso8601String();
            try {
              await db.insert('conversation_participants', {
                'id': 'p_${widget.groupId}_${u['id']}',
                'conversation_id': widget.groupId,
                'user_id': u['id'],
                'role': 'member',
                'joined_at': now,
                'is_muted': 0,
                'is_pinned': 0,
                'unread_count': 0,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            } catch (_) {}
            if (context.mounted) Navigator.pop(context);
          },
        )).toList(),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
    await _load();
  }

  Future<void> _removeMember(String userId) async {
    final db = await DatabaseService.instance.database;
    if (userId == _uid) return; // use Leave Group instead
    if (userId == _ownerId) return; // Transfer ownership first.
    await db.delete('conversation_participants', where: 'conversation_id = ? AND user_id = ?', whereArgs: [widget.groupId, userId]);
    await _load();
  }

  Future<void> _toggleAdmin(String userId, bool promote) async {
    if (!_isAdmin && userId != _uid) return;
    if (userId == _ownerId && !promote) return; // Owner role is protected.
    final db = await DatabaseService.instance.database;
    final admins = _members.where((m) => (m['role'] as String) == 'admin' || (m['role'] as String) == 'owner').length;
    // Prevent removing the last admin's admin role.
    if (!promote && userId == _uid && admins <= 1) return;
    final role = promote ? 'admin' : 'member';
    await db.update('conversation_participants', {'role': role}, where: 'conversation_id = ? AND user_id = ?', whereArgs: [widget.groupId, userId]);
    await _load();
  }

  Future<void> _transferOwnership() async {
    if (!_isOwner) return;
    final db = await DatabaseService.instance.database;
    final eligible = _members.where((m) => m['user_id'] != _uid).toList();
    if (!mounted) return;
    final confirmedTo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer ownership'),
        content: eligible.isEmpty
            ? const Text('No eligible members')
            : Column(mainAxisSize: MainAxisSize.min, children: eligible
                .map((m) => ListTile(
                      title: Text((m['display_name'] as String?) ?? m['user_id'].toString()),
                      onTap: () => Navigator.pop(context, m['user_id'] as String),
                    ))
                .toList()),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
    if (confirmedTo == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Confirm transfer'),
      content: const Text('You will remain a group admin. Continue?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transfer')),
      ],
    ));
    if (ok != true || !mounted) return;
    await GroupService.transferOwnership(db, widget.groupId, _uid, confirmedTo);
    await _load();
  }

  Future<void> _leaveGroup() async {
    final db = await DatabaseService.instance.database;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Leave group?'),
      content: const Text('You will stop receiving messages for this group.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    await db.delete('conversation_participants', where: 'conversation_id = ? AND user_id = ?', whereArgs: [widget.groupId, _uid]);
    if (mounted) context.pop();
  }

  Future<void> _changeImage() async {
    if (!_isAdmin) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/group_${widget.groupId}_${DateTime.now().millisecondsSinceEpoch}.png');
    try {
      await file.writeAsBytes(await picked.readAsBytes());
    } catch (_) {
      return;
    }
    final db = await DatabaseService.instance.database;
    await GroupService.setGroupImage(db, widget.groupId, _uid, file.path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const QivoraBackButton(fallbackRoute: '/groups'),
        title: Text((_group?['title'] as String?) ?? 'Group'),
        actions: [
          if (_isAdmin) IconButton(icon: const Icon(Icons.person_add), onPressed: _addMember),
          if (_isOwner) IconButton(icon: const Icon(Icons.swap_horiz), tooltip: 'Transfer ownership', onPressed: _transferOwnership),
          IconButton(icon: const Icon(Icons.picture_in_picture_alt), tooltip: 'Change image', onPressed: _changeImage),
          IconButton(icon: const Icon(Icons.chat_rounded), onPressed: () => context.push('/chat/${widget.groupId}')),
          IconButton(icon: const Icon(Icons.logout), onPressed: _leaveGroup),
        ],
      ),
      body: _group == null
          ? const Center(child: Text('Group not found'))
          : Column(children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundImage: _group!['avatar_path'] != null
                      ? FileImage(File(_group!['avatar_path'] as String))
                      : null,
                  child: _group!['avatar_path'] != null
                      ? null
                      : const Icon(Icons.group),
                ),
                title: Text(_group!['title'] as String),
                subtitle: Text('${_members.length} members'),
              ),
              Expanded(
                child: _members.isEmpty
                    ? const Center(child: Text('No members'))
                    : ListView.builder(
                        itemCount: _members.length,
                        itemBuilder: (_, i) {
                          final m = _members[i];
                          final isAdmin = m['role'] == 'admin';
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text((m['display_name'] as String?) ?? m['user_id'].toString()),
                            subtitle: Text(m['user_id'].toString()),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (isAdmin)
                                const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.shield, color: Color(0xFF00A878), size: 18)),
                              if (_isAdmin && m['user_id'] != _uid) ...[
                                IconButton(icon: Icon(isAdmin ? Icons.shield_outlined : Icons.shield), tooltip: isAdmin ? 'Demote' : 'Promote', onPressed: () => _toggleAdmin(m['user_id'] as String, !isAdmin)),
                                IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: 'Remove', onPressed: () => _removeMember(m['user_id'] as String)),
                              ],
                            ]),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

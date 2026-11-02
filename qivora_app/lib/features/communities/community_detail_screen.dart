import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_colors.dart';
import 'community_service.dart';

/// Community details: info, linked groups, members, management actions.
class CommunityDetailScreen extends StatefulWidget {
  final String communityId;
  const CommunityDetailScreen({super.key, required this.communityId});
  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _members = [];
  String _uid = 'me';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id') ?? 'me';
    final db = await DatabaseService.instance.database;
    final c = await db
        .query('communities', where: 'id = ?', whereArgs: [widget.communityId]);
    final g = await db.rawQuery('''
      SELECT cgv.id, cgv.title, cgv.avatar_path, COUNT(p.id) AS members
      FROM community_groups cg
      JOIN conversations cgv ON cgv.id = cg.conversation_id
      LEFT JOIN conversation_participants p ON p.conversation_id = cgv.id
      WHERE cg.community_id = ?
      GROUP BY cgv.id
      ORDER BY cgv.title
    ''', [widget.communityId]);
    final m = await db.rawQuery('''
      SELECT cm.user_id, cm.role, u.display_name
      FROM community_members cm
      LEFT JOIN users u ON u.id = cm.user_id
      WHERE cm.community_id = ?
      ORDER BY CASE cm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, cm.user_id
    ''', [widget.communityId]);
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _community = c.isEmpty ? null : c.first;
      _groups = g;
      _members = m;
      _loading = false;
    });
  }

  bool get _isManager => _members
      .any((m) => m['user_id'] == _uid && (m['role'] == 'admin' || m['role'] == 'owner'));
  bool get _isOwner => _community?['owner_user_id'] == _uid;

  Future<void> _addGroup() async {
    if (!_isManager) return;
    final db = await DatabaseService.instance.database;
    final available = await db.rawQuery('''
      SELECT c.id, c.title FROM conversations c
      WHERE c.type = 'group'
        AND c.id NOT IN (SELECT conversation_id FROM community_groups WHERE community_id = ?)
    ''', [widget.communityId]);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add group'),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: available.isEmpty
              ? const Center(child: Text('No groups available'))
              : ListView(
                  children: available
                      .map((c) => ListTile(
                            title: Text(c['title'] as String? ?? c['id'].toString()),
                            onTap: () async {
                              await CommunityService.addGroup(db,
                                  widget.communityId, c['id'] as String, _uid);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
    await _load();
  }

  Future<void> _removeGroup(String conversationId) async {
    if (!_isManager) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove group?'),
        content: const Text(
            'The group, its members and its messages will remain and can be added to another community later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await DatabaseService.instance.database;
    await CommunityService.removeGroup(
        db, widget.communityId, conversationId, _uid);
    await _load();
  }

  Future<void> _addMember() async {
    if (!_isManager) return;
    final db = await DatabaseService.instance.database;
    final users = await db.query('users');
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add member'),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: ListView(
            children: users
                .where((u) => !_members.any((m) => m['user_id'] == u['id']))
                .map((u) => ListTile(
                      title: Text((u['display_name'] as String?) ?? u['id'].toString()),
                      onTap: () async {
                        await CommunityService.addMember(db,
                            widget.communityId, u['id'] as String, _uid);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
    await _load();
  }

  Future<void> _changeRole(String userId, bool promote) async {
    if (!_isOwner) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(promote ? 'Promote to admin?' : 'Demote admin?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(promote ? 'Promote' : 'Demote')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await DatabaseService.instance.database;
    final ok = await CommunityService.setMemberRole(
        db, widget.communityId, userId, _uid, promote);
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role change not permitted')));
    }
    await _load();
  }

  Future<void> _removeMember(String userId) async {
    final db = await DatabaseService.instance.database;
    final ok = await CommunityService.removeMember(
        db, widget.communityId, userId, _uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Member removed'
              : 'Not permitted — the owner cannot be removed here')));
    }
    await _load();
  }

  Future<void> _leaveCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave community?'),
        content: const Text(
            'If you are the owner, the oldest remaining member becomes the new owner.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = await DatabaseService.instance.database;
    await CommunityService.leaveCommunity(db, widget.communityId, _uid);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_community == null) {
      return const Scaffold(body: Center(child: Text('Community not found')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_community!['name'] as String),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Leave community',
              onPressed: _leaveCommunity,
            )
          else if (_members.any((m) => m['user_id'] == _uid))
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Leave community',
              onPressed: _leaveCommunity,
            ),
        ],
      ),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(
            backgroundImage: _community!['avatar_path'] != null
                ? FileImage(
                    File(_community!['avatar_path'] as String))
                : null,
            child: _community!['avatar_path'] != null
                ? null
                : const Icon(Icons.groups_2),
          ),
          title: Text(_community!['name'] as String),
          subtitle: Text((_community!['description'] as String?) ?? ''),
        ),
        const SectionLabel('Groups'),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add group'),
          onTap: _isManager ? _addGroup : null,
        ),
        ..._groups.map((g) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.tag)),
              title: Text(g['title'] as String? ?? g['id'].toString()),
              subtitle: Text('${g['members']} members'),
              onTap: () => context.push('/chat/${g['id']}'),
              trailing: _isManager
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove from community',
                      onPressed: () => _removeGroup(g['id'] as String),
                    )
                  : null,
            )),
        const SectionLabel('Members'),
        ListTile(
          leading: const Icon(Icons.person_add),
          title: const Text('Add member'),
          onTap: _isManager ? _addMember : null,
        ),
        ..._members.map((m) {
          final isOwnerRow = m['role'] == 'owner';
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text((m['display_name'] as String?) ?? m['user_id'].toString()),
            subtitle: Text(m['user_id'].toString()),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (isOwnerRow)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('Owner',
                      style: TextStyle(color: AppColors.primary, fontSize: 12)),
                )
              else if (m['role'] == 'admin')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('Admin',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              if (_isOwner && m['user_id'] != _uid) ...[
                IconButton(
                  icon: Icon(m['role'] == 'admin'
                      ? Icons.shield_outlined
                      : Icons.shield),
                  tooltip:
                      m['role'] == 'admin' ? 'Demote admin' : 'Promote to admin',
                  onPressed: () =>
                      _changeRole(m['user_id'] as String, m['role'] != 'admin'),
                ),
              ],
              if (_isManager && m['user_id'] != _uid)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove member',
                  onPressed: () => _removeMember(m['user_id'] as String),
                ),
            ]),
          );
        }),
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );
}

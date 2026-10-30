import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/auth/status_privacy.dart';
import '../../core/database/database_service.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});
  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<Map<String, dynamic>> _statuses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _markViewed(String statusId) async {
    final db = await DatabaseService.instance.database;
    await db.insert('status_views', {'status_id': statusId, 'viewer_id': 'me', 'created_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query('statuses',
        where: 'expires_at > ?', whereArgs: [now], orderBy: 'created_at DESC');
    if (mounted) setState(() => _statuses = rows);
  }

  Future<void> _showViewers(String statusId) async {
    final db = await DatabaseService.instance.database;
    final views = await db.rawQuery('''
      SELECT sv.viewer_id, sv.created_at, u.display_name
      FROM status_views sv
      LEFT JOIN users u ON u.id = sv.viewer_id
      WHERE sv.status_id = ?
      ORDER BY sv.created_at DESC
    ''', [statusId]);
    final privacy = (await db.query('privacy_settings', where: 'key = ?', whereArgs: ['status_privacy']).then((r) => r.isEmpty ? 'all' : (r.first['value'] as String? ?? 'all')));
    final contacts = (await db.query('contacts').then((r) => r.map((row) => row['contact_user_id'] as String).toSet()));
    final eligible = views.where((v) => canViewStatus(
      ownerId: 'me',
      viewerId: v['viewer_id'].toString(),
      privacy: privacy,
      contacts: contacts,
    ));
    final shown = eligible.where((v) => v['viewer_id'].toString() != 'me').toList();
    if (!mounted) return;
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text('Viewers (${shown.length})'),
      content: shown.isEmpty
          ? const Text('No viewers yet')
          : Column(mainAxisSize: MainAxisSize.min, children: [
              ...shown.map((v) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text((v['display_name'] as String?) ?? v['viewer_id'].toString()),
                    subtitle: Text(v['created_at'].toString()),
                  )),
            ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Future<void> _createStatus() async {
    final ctl = TextEditingController();
    String privacy = 'all';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Status'),
        content: StatefulBuilder(builder: (context, setDlg) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ctl, decoration: const InputDecoration(labelText: 'What is on your mind?'), maxLines: 3),
            DropdownButtonFormField<String>(
              initialValue: privacy,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Everyone (local only)')),
                DropdownMenuItem(value: 'contacts', child: Text('My contacts')),
                DropdownMenuItem(value: 'except', child: Text('My contacts except...')),
                DropdownMenuItem(value: 'only', child: Text('Only share with...')),
              ],
              onChanged: (v) => setDlg(() => privacy = v ?? 'all'),
              decoration: const InputDecoration(labelText: 'Privacy'),
            ),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final text = ctl.text.trim();
              if (text.isEmpty) return;
              final db = await DatabaseService.instance.database;
              await db.insert('privacy_settings', {'key': 'status_privacy', 'value': privacy});
              final now = DateTime.now();
              await db.insert('statuses', {
                'id': const Uuid().v4(),
                'user_id': 'me',
                'content': text,
                'background_color': '#00A878',
                'created_at': now.toIso8601String(),
                'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createStatus,
        child: const Icon(Icons.edit),
      ),
      body: _statuses.isEmpty
          ? const Center(child: Text('No recent updates'))
          : ListView.builder(
              itemCount: _statuses.length,
              itemBuilder: (_, i) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text((_statuses[i]['content'] as String?) ?? ''),
                subtitle: Text(_statuses[i]['created_at'].toString()),
                onTap: () async {
                  await _markViewed(_statuses[i]['id'] as String);
                  if (mounted) await _load();
                  if (mounted) _showViewers(_statuses[i]['id'] as String);
                },
              ),
            ),
    );
  }
}

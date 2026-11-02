import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/auth/status_service.dart';
import '../../core/database/database_service.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});
  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<Map<String, dynamic>> _statuses = [];
  final String _uid = 'me';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _markViewed(String statusId) async {
    final db = await DatabaseService.instance.database;
    // Permission is validated at the service layer; unauthorized viewers are
    // not recorded and get no access to viewer data.
    await StatusService.recordStatusView(db, statusId, _uid);
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await StatusService.visibleStatuses(db, _uid);
    if (mounted) setState(() => _statuses = rows);
  }

  Future<void> _showViewers(String statusId) async {
    final db = await DatabaseService.instance.database;
    final views = await StatusService.viewsOf(db, statusId);
    final shown =
        views.where((v) => v['viewer_id'].toString() != _uid).toList();
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Viewers (${shown.length})'),
              content: shown.isEmpty
                  ? const Text('No viewers yet')
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      ...shown.map((v) => ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(
                                (v['display_name'] as String?) ??
                                    v['viewer_id'].toString()),
                            subtitle: Text(v['created_at'].toString()),
                          )),
                    ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  Future<void> _pickSet(Set<String> pool, Set<String> initial) async {
    final selected = Set<String>.from(initial);
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('Choose contacts'),
          content: SizedBox(
            width: double.maxFinite,
            height: 250,
            child: pool.isEmpty
                ? const Center(child: Text('No contacts'))
                : ListView(
                    children: pool.map((c) {
                      final checked = selected.contains(c);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(c),
                        onChanged: (v) =>
                            setDlg(() => v == true ? selected.add(c) : selected.remove(c)),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      ),
    );
    initial
      ..clear()
      ..addAll(selected);
  }

  Future<void> _createStatus() async {
    final ctl = TextEditingController();
    String privacy = 'all';
    final except = <String>{};
    final only = <String>{};
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Status'),
        content: StatefulBuilder(
          builder: (context, setDlg) => Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: ctl,
                decoration: const InputDecoration(labelText: 'What is on your mind?'),
                maxLines: 3),
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
            if (privacy == 'except')
              TextButton(
                onPressed: () async {
                  final db = await DatabaseService.instance.database;
                  final pool = await StatusService.contactsOf(db, _uid);
                  await _pickSet(pool, except);
                  setDlg(() {});
                },
                child: Text('Except list (${except.length})'),
              ),
            if (privacy == 'only')
              TextButton(
                onPressed: () async {
                  final db = await DatabaseService.instance.database;
                  final pool = await StatusService.contactsOf(db, _uid);
                  await _pickSet(pool, only);
                  setDlg(() {});
                },
                child: Text('Shared list (${only.length})'),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final text = ctl.text.trim();
              if (text.isEmpty) return;
              final db = await DatabaseService.instance.database;
              await StatusService.createStatus(
                db,
                _uid,
                text,
                privacy,
                except: except,
                only: only,
              );
              // Keep the global default in sync for backwards compatibility.
              await db.insert(
                  'privacy_settings',
                  {'key': 'status_privacy', 'value': privacy},
                  conflictAlgorithm: ConflictAlgorithm.replace);
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

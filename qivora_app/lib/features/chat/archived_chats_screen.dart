import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/database_service.dart';
import '../../core/widgets/qivora_back_button.dart';

/// Dedicated screen listing archived conversations with unarchive support.
class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});
  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.title, c.updated_at, m.content AS last_message
      FROM conversations c
      LEFT JOIN messages m ON m.id = c.last_message_id
      WHERE c.archived = 1
      ORDER BY c.updated_at DESC
    ''');
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _unarchive(String id) async {
    final db = await DatabaseService.instance.database;
    await db.update('conversations', {'archived': 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const QivoraBackButton(fallbackRoute: '/home'),
        title: const Text('Archived Chats'),
      ),
      body: _rows.isEmpty
          ? const Center(child: Text('No archived chats'))
          : ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final r = _rows[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.archive)),
                  title: Text(r['title'] as String? ?? ''),
                  subtitle: Text((r['last_message'] as String?) ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.unarchive),
                    tooltip: 'Unarchive',
                    onPressed: () => _unarchive(r['id'] as String),
                  ),
                  onTap: () => context.push('/chat/${r['id']}'),
                );
              },
            ),
    );
  }
}

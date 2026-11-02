import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/database_service.dart';
import '../../core/widgets/qivora_back_button.dart';

/// Dedicated screen listing starred messages grouped by conversation.
class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});
  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery('''
      SELECT m.id, m.content, m.created_at, m.conversation_id, c.title
      FROM messages m
      LEFT JOIN conversations c ON c.id = m.conversation_id
      WHERE m.starred = 1
      ORDER BY m.created_at DESC
    ''');
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _unstar(String id) async {
    final db = await DatabaseService.instance.database;
    await db.update('messages', {'starred': 0}, where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const QivoraBackButton(fallbackRoute: '/home'),
        title: const Text('Starred Messages'),
      ),
      body: _rows.isEmpty
          ? const Center(child: Text('No starred messages'))
          : ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final r = _rows[i];
                return ListTile(
                  leading: const Icon(Icons.star, color: Color(0xFFF59E0B)),
                  title: Text((r['content'] as String?) ?? ''),
                  subtitle: Text((r['title'] as String?) ?? 'Conversation'),
                  trailing: IconButton(
                    icon: const Icon(Icons.star_border),
                    tooltip: 'Unstar',
                    onPressed: () => _unstar(r['id'] as String),
                  ),
                  onTap: () => context.push('/chat/${r['conversation_id']}'),
                );
              },
            ),
    );
  }
}

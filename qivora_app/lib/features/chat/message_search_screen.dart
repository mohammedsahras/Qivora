import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/qivora_back_button.dart';

class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({super.key});

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = trimmed;
      _loading = true;
      _error = null;
    });
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.rawQuery('''
        SELECT m.id, m.content, m.created_at, m.conversation_id, c.title AS conversation_title
        FROM messages m
        LEFT JOIN conversations c ON c.id = m.conversation_id
        WHERE m.deleted_at IS NULL AND LOWER(m.content) LIKE LOWER(?)
        ORDER BY m.created_at DESC
        LIMIT 50
      ''', ['%$trimmed%']);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Widget _highlight(String text, String query) {
    if (query.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;
    while ((idx = lower.indexOf(q, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: const TextStyle(
            fontWeight: FontWeight.bold, color: AppColors.primary),
      ));
      start = idx + q.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(
        text: TextSpan(
            style: DefaultTextStyle.of(context).style, children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: const QivoraBackButton(fallbackRoute: '/home'),
        title: const Text('Search Messages'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              onChanged: (v) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_ctrl.text == v) _search(v);
                });
              },
              decoration: InputDecoration(
                hintText: 'Search messages',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _search('');
                        },
                        tooltip: 'Clear search',
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty ? 'Type to search' : 'No results',
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textMain),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final r = _results[i];
                              return ListTile(
                                title: _highlight(
                                    r['content'] as String? ?? '', _query),
                                subtitle: Text(
                                    r['conversation_title'] as String? ?? ''),
                                trailing:
                                    Text(r['created_at'] as String? ?? ''),
                                onTap: () {
                                  context.go(
                                      '/chat/${r['conversation_id']}?title=${Uri.encodeComponent(r['conversation_title'] as String? ?? 'Conversation')}');
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

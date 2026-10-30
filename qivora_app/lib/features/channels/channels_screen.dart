import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database_service.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Map<String, dynamic>> _channels = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('channels', orderBy: 'updated_at DESC');
    if (mounted) setState(() => _channels = rows);
  }

  List<Map<String, dynamic>> get _filtered => _channels
      .where((c) => (c['name'] as String).toLowerCase().contains(_query.toLowerCase()))
      .toList();

  Future<void> _createChannel() async {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Channel'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Channel name')),
          TextField(controller: descCtl, decoration: const InputDecoration(labelText: 'Description')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              final db = await DatabaseService.instance.database;
              final now = DateTime.now().toIso8601String();
              await db.insert('channels', {'id': const Uuid().v4(), 'name': name, 'description': descCtl.text.trim(), 'category': 'general', 'created_at': now, 'updated_at': now});
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Channels')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createChannel,
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search channels', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: _query.isEmpty || _filtered.isNotEmpty
              ? ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.campaign)),
                    title: Text(_filtered[i]['name'] as String),
                    subtitle: Text((_filtered[i]['description'] as String?) ?? ''),
                    onTap: () => context.push('/channels/detail/${_filtered[i]['id']}'),
                  ),
                )
              : const Center(child: Text('No channels found')),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database_service.dart';

class ChannelDetailScreen extends StatefulWidget {
  final String channelId;
  const ChannelDetailScreen({super.key, required this.channelId});
  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen> {
  Map<String, dynamic>? _channel;
  List<Map<String, dynamic>> _updates = [];
  List<Map<String, dynamic>> _admins = [];
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> get _uid async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'me';
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final ch = await db.query('channels', where: 'id = ?', whereArgs: [widget.channelId]);
    final up = await db.query('channel_updates', where: 'channel_id = ?', whereArgs: [widget.channelId], orderBy: 'created_at DESC');
    final following = await db.query('channel_followers', where: 'channel_id = ? AND user_id = ?', whereArgs: [widget.channelId, await _uid]);
    final admins = await db.query('channel_admins', where: 'channel_id = ?', whereArgs: [widget.channelId]);
    if (!mounted) return;
    setState(() {
      _channel = ch.isEmpty ? null : ch.first;
      _updates = up;
      _isFollowing = following.isNotEmpty;
      _admins = admins;
    });
  }

  Future<void> _toggleFollow() async {
    final db = await DatabaseService.instance.database;
    if (_isFollowing) {
      await db.delete('channel_followers', where: 'channel_id = ? AND user_id = ?', whereArgs: [widget.channelId, await _uid]);
    } else {
      await db.insert('channel_followers', {'channel_id': widget.channelId, 'user_id': await _uid, 'created_at': DateTime.now().toIso8601String()});
    }
    await _load();
  }

  Future<void> _publishUpdate() async {
    final ctl = TextEditingController();
    await showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('New update'),
      content: TextField(controller: ctl, maxLines: 3, decoration: const InputDecoration(labelText: 'Update text')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (ctl.text.trim().isEmpty) return;
          final db = await DatabaseService.instance.database;
          await db.insert('channel_updates', {'id': const Uuid().v4(), 'channel_id': widget.channelId, 'content': ctl.text.trim(), 'created_at': DateTime.now().toIso8601String()});
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('Publish')),
      ],
    ));
    await _load();
  }

  Future<void> _manageAdmins() async {
    final db = await DatabaseService.instance.database;
    final users = await db.query('users');
    if (!mounted) return;
    await showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
      List<Map<String, dynamic>> localAdmins = [];
      Future<void> loadAdmins() async {
        localAdmins = await db.query('channel_admins', where: 'channel_id = ?', whereArgs: [widget.channelId]);
        setDialogState(() {});
      }
      loadAdmins();
      return AlertDialog(
        title: const Text('Channel admins'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ...localAdmins.map((a) => ListTile(
              title: Text(a['user_id'].toString()),
              trailing: IconButton(icon: const Icon(Icons.remove), onPressed: () async {
                await db.delete('channel_admins', where: 'channel_id = ? AND user_id = ?', whereArgs: [widget.channelId, a['user_id']]);
                await loadAdmins();
              }),
            )),
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Add admin'),
              items: users.map((u) => DropdownMenuItem(value: u['id'].toString(), child: Text(u['id'].toString()))).toList(),
              onChanged: (v) async {
                if (v == null) return;
                final exists = await db.query('channel_admins', where: 'channel_id = ? AND user_id = ?', whereArgs: [widget.channelId, v]);
                if (exists.isEmpty) {
                  await db.insert('channel_admins', {'channel_id': widget.channelId, 'user_id': v, 'created_at': DateTime.now().toIso8601String()});
                }
                await loadAdmins();
              },
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      );
    }));
    await _load();
  }

  Future<void> _editChannel() async {
    final nameCtl = TextEditingController(text: _channel?['name'] as String?);
    final descCtl = TextEditingController(text: (_channel?['description'] ?? '') as String);
    await showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Edit channel'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Name')),
        TextField(controller: descCtl, decoration: const InputDecoration(labelText: 'Description')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final db = await DatabaseService.instance.database;
          await db.update('channels', {'name': nameCtl.text.trim(), 'description': descCtl.text.trim(), 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [widget.channelId]);
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('Save')),
      ],
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text((_channel?['name'] as String?) ?? 'Channel'), actions: [
        IconButton(icon: const Icon(Icons.edit), onPressed: _editChannel),
        IconButton(icon: const Icon(Icons.admin_panel_settings), onPressed: _manageAdmins),
        IconButton(icon: const Icon(Icons.add), onPressed: _publishUpdate),
      ]),
      body: _channel == null ? const Center(child: Text('Channel not found')) : Column(
        children: [
          SwitchListTile(
            title: Text(_isFollowing ? 'Following' : 'Not following'),
            subtitle: Text('${_admins.length} admins'),
            value: _isFollowing,
            onChanged: (_) => _toggleFollow(),
          ),
          Expanded(
            child: _updates.isEmpty ? const Center(child: Text('No updates')) : ListView.builder(
              itemCount: _updates.length,
              itemBuilder: (_, i) => ListTile(title: Text((_updates[i]['content'] as String?) ?? ''), subtitle: Text(_updates[i]['created_at'].toString())),
            ),
          ),
        ],
      ),
    );
  }
}

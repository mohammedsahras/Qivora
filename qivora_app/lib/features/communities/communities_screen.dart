import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_colors.dart';
import 'community_service.dart';

/// Communities list with search and creation dialog.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.description, c.avatar_path,
             COUNT(DISTINCT cg.conversation_id) AS group_count
      FROM communities c
      LEFT JOIN community_groups cg ON cg.community_id = c.id
      GROUP BY c.id
      ORDER BY c.updated_at DESC
    ''');
    if (!mounted) return;
    setState(() {
      _communities = rows;
      _loading = false;
      _applyFilter();
    });
  }

  void _applyFilter() {
    setState(() {
      _filtered = _query.isEmpty
          ? _communities
          : _communities
              .where((c) => (c['name'] as String)
                  .toLowerCase()
                  .contains(_query.toLowerCase()))
              .toList();
    });
  }

  Future<void> _createCommunity() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String? imagePath;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New community'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Community name'),
            ),
            TextField(
              controller: descController,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.image),
              label: Text(imagePath == null ? 'Add image' : 'Change image'),
              onPressed: () async {
                final picked = await ImagePicker()
                    .pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (picked == null) return;
                final dir = await getApplicationDocumentsDirectory();
                final file = File(
                    '${dir.path}/community_${const Uuid().v4()}.png');
                try {
                  await file.writeAsBytes(await picked.readAsBytes());
                } catch (_) {
                  return;
                }
                setDialogState(() => imagePath = file.path);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id') ?? 'me';
    final db = await DatabaseService.instance.database;
    final name = nameController.text.trim();
    if (!mounted) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community name is required')));
      return;
    }
    final id = await CommunityService.createCommunity(
        db, name, descController.text, uid, imagePath);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A community with this name already exists')));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Communities')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _createCommunity,
        child: const Icon(Icons.groups_2),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search communities',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              _query = v;
              _applyFilter();
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? const Center(child: Text('No communities yet'))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: c['avatar_path'] != null
                                ? FileImage(File(c['avatar_path'] as String))
                                : null,
                            child: c['avatar_path'] != null
                                ? null
                                : const Icon(Icons.groups_2),
                          ),
                          title: Text(c['name'] as String),
                          subtitle: Text('${c['group_count']} groups'),
                          onTap: () =>
                              context.push('/communities/detail/${c['id']}'),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

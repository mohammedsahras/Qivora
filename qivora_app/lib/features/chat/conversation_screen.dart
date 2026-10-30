import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../core/database/database_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/qivora_avatar.dart';
import '../../core/widgets/qivora_message_bubble.dart';

/// Individual conversation screen.
///
/// Displays real messages from SQLite with visually distinct incoming and
/// outgoing bubbles, real timestamps, and delivery status read from the
/// database. Messages are persisted locally — Qivora has no cross-device
/// messaging backend, so delivery/read status reflects local storage only.
class ConversationScreen extends StatefulWidget {
  final String conversationId;
  final String conversationTitle;
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.conversationTitle,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  String? _error;
  final ScrollController _scroll = ScrollController();
  String _currentUserId = 'me';
  bool _sending = false;
  bool _loadingMore = false;
  bool _hasReachedStart = false;

  /// Id of the message being replied to, or null.
  String? _replyToId;
  String? _replyToText;

  static const int _pageSize = 30;

  /// Voice recording state.
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  String? _recordingPath;
  String? _currentlyPlayingMessageId;

  /// Cache of message_id -> list of reaction rows.
  Map<String, List<Map<String, dynamic>>> _reactionCache = {};

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _load();
    _loadDraft();
    _ctrl.addListener(_onDraftChanged);
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted && state.processingState == ProcessingState.completed) {
        setState(() => _currentlyPlayingMessageId = null);
      }
    });
  }

  Future<void> _loadDraft() async {
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'drafts',
        where: 'conversation_id = ?',
        whereArgs: [widget.conversationId],
      );
      if (rows.isNotEmpty && mounted) {
        _ctrl.text = rows.first['draft_text'] as String? ?? '';
      }
    } catch (_) {}
  }

  void _onDraftChanged() {
    _saveDraftDebounced();
  }

  Future<void> _saveDraftDebounced() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final text = _ctrl.text;
    try {
      final db = await DatabaseService.instance.database;
      if (text.trim().isEmpty) {
        await db.delete(
          'drafts',
          where: 'conversation_id = ?',
          whereArgs: [widget.conversationId],
        );
      } else {
        await db.insert(
          'drafts',
          {
            'conversation_id': widget.conversationId,
            'draft_text': text,
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentUserId = prefs.getString('user_id') ?? 'me';
    });
  }

  Future<void> _load({bool loadMore = false}) async {
    if (loadMore) {
      if (_loadingMore || _hasReachedStart) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _hasReachedStart = false;
      });
    }
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'messages',
        where:
            'conversation_id = ? AND deleted_at IS NULL ${loadMore ? 'AND created_at < ?' : ''}',
        whereArgs: loadMore
            ? [widget.conversationId, _msgs.first['created_at'] as String]
            : [widget.conversationId],
        orderBy: 'created_at ASC',
        limit: loadMore ? _pageSize : null,
        offset: loadMore ? 0 : null,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _msgs = [...rows.reversed, ..._msgs];
          _loadingMore = false;
          if (rows.length < _pageSize) _hasReachedStart = true;
        } else {
          _msgs = rows;
          _loading = false;
        }
        _scrollToBottom(animate: !loadMore);
      });
      // Load reactions for the displayed messages.
      _reactionCache = await _loadReactions();
      // Mark conversation as read.
      await _markConversationAsRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_msgs.isEmpty) return;
    final position = _scroll.position.pixels;
    final maxBefore = _scroll.position.maxScrollExtent;
    await _load(loadMore: true);
    if (!mounted) return;
    final maxAfter = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(position + (maxAfter - maxBefore));
  }

  Future<void> _retry() => _load();

  Future<void> _scrollToBottom({bool animate = false}) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!_scroll.hasClients || !mounted) return;
    if (animate) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  MessageDeliveryStatus _status(String? raw) {
    switch (raw) {
      case 'delivered':
        return MessageDeliveryStatus.delivered;
      case 'read':
        return MessageDeliveryStatus.read;
      default:
        return MessageDeliveryStatus.sent;
    }
  }

  bool _getBool(dynamic v) => (v as int?) == 1;

  /// Sends a text message. Guarded against duplicate taps while a send is
  /// in flight. Persists to SQLite immediately so the message appears at once.
  Future<void> _send() async {
    if (_sending) return;
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;

    setState(() => _sending = true);
    try {
      final db = await DatabaseService.instance.database;
      final id = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      await db.insert(
        'messages',
        {
          'id': id,
          'conversation_id': widget.conversationId,
          'sender_id': _currentUserId,
          'message_type': 'text',
          'content': t,
          'reply_to_message_id': _replyToId,
          'delivery_status': 'sent',
          'created_at': now,
          'updated_at': now,
        },
      );
      await db.update(
        'conversations',
        {'last_message_id': id, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [widget.conversationId],
      );
      _ctrl.clear();
      _setReply(null, null);
      try {
        final db = await DatabaseService.instance.database;
        await db.delete(
          'drafts',
          where: 'conversation_id = ?',
          whereArgs: [widget.conversationId],
        );
      } catch (_) {}
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $e. Tap Retry below.'),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _send,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setReply(String? id, String? text) {
    setState(() {
      _replyToId = id;
      _replyToText = text;
    });
  }

  /// Attaches an image from the gallery or camera. The file is copied into
  /// the app's documents directory and stored as an image message.
  Future<void> _attachImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1600,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showError('Attachment failed: ${e.message ?? e}');
      return;
    } catch (e) {
      if (!mounted) return;
      _showError('Attachment failed: $e');
      return;
    }
    if (picked == null) return; // user cancelled
    _saveAttachment(picked);
  }

  /// Attaches a document using the system file picker.
  Future<void> _attachFile() async {
    String? path;
    try {
      final results = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'jpg',
          'jpeg',
          'png',
          'webp',
        ],
      );
      path = results.isNotEmpty ? results.first.path : null;
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showError('File selection failed: ${e.message ?? e}');
      return;
    } catch (e) {
      if (!mounted) return;
      _showError('File selection failed: $e');
      return;
    }
    if (path == null) return; // user cancelled
    _saveAttachment(XFile(path));
  }

  Future<void> _saveAttachment(XFile file) async {
    final ext = p.extension(file.path).toLowerCase().replaceFirst('.', '');
    final allowed = {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'pdf',
      'doc',
      'docx',
      'txt',
    };
    if (!allowed.contains(ext)) {
      if (!mounted) return;
      _showError('File type ".$ext" is not supported.');
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${dir.path}/Qivora/attachments');
      if (!await attachDir.exists()) await attachDir.create(recursive: true);
      final name = '${const Uuid().v4()}.$ext';
      final source = File(file.path);
      final saved = await source.copy('${attachDir.path}/$name');
      final stat = await saved.stat();
      final db = await DatabaseService.instance.database;
      final now = DateTime.now().toIso8601String();
      final id = const Uuid().v4();
      final isImage = {'jpg', 'jpeg', 'png', 'webp'}.contains(ext);
      await db.insert(
        'messages',
        {
          'id': id,
          'conversation_id': widget.conversationId,
          'sender_id': _currentUserId,
          'message_type': isImage ? 'image' : 'file',
          'content': file.name,
          'attachment_path': saved.path,
          'attachment_filename': file.name,
          'attachment_size': stat.size,
          'attachment_type': isImage ? 'image/$ext' : _mimeType(ext),
          'delivery_status': 'sent',
          'created_at': now,
          'updated_at': now,
        },
      );
      await db.update(
        'conversations',
        {'last_message_id': id, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [widget.conversationId],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Attachment save failed: $e');
    }
  }

  String _mimeType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// Start recording a voice message. Checks microphone permission first.
  Future<void> _startVoiceRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        _showError(
            'Microphone permission is required to record voice messages.');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${dir.path}/Qivora/voice');
      if (!await voiceDir.exists()) await voiceDir.create(recursive: true);
      final path = '${voiceDir.path}/voice_${const Uuid().v4()}.m4a';
      await _audioRecorder.start(
        const RecordConfig(),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordDuration = Duration.zero;
      });
      _startRecordTimer();
    } catch (e) {
      if (!mounted) return;
      _showError('Recording failed: $e');
    }
  }

  void _startRecordTimer() {
    if (!_isRecording) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_isRecording) return;
      setState(() {
        _recordDuration = _recordDuration + const Duration(seconds: 1);
      });
      _startRecordTimer();
    });
  }

  /// Stop recording and send the voice message.
  Future<void> _stopVoiceRecording() async {
    if (_recordingPath == null) return;
    await _audioRecorder.stop();
    if (!mounted) return;
    setState(() => _isRecording = false);
    await _saveVoiceMessage(_recordingPath!);
    _recordingPath = null;
    _recordDuration = Duration.zero;
  }

  /// Cancel recording and delete the temporary file.
  Future<void> _cancelVoiceRecording() async {
    await _audioRecorder.stop();
    if (_recordingPath != null) {
      try {
        await File(_recordingPath!).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingPath = null;
      _recordDuration = Duration.zero;
    });
  }

  Future<void> _saveVoiceMessage(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final stat = await file.stat();
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    final id = const Uuid().v4();
    await db.insert(
      'messages',
      {
        'id': id,
        'conversation_id': widget.conversationId,
        'sender_id': _currentUserId,
        'message_type': 'audio',
        'content': 'Voice message',
        'audio_path': path,
        'media_duration': stat.size ~/ 1024,
        'delivery_status': 'sent',
        'created_at': now,
        'updated_at': now,
      },
    );
    await db.update(
      'conversations',
      {'last_message_id': id, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [widget.conversationId],
    );
    await _load();
  }

  /// Play or pause a voice message.
  Future<void> _toggleVoicePlayback(String messageId, String audioPath) async {
    if (_currentlyPlayingMessageId == messageId) {
      await _audioPlayer.pause();
      setState(() => _currentlyPlayingMessageId = null);
      return;
    }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(audioPath);
      await _audioPlayer.play();
      if (!mounted) return;
      setState(() => _currentlyPlayingMessageId = messageId);
    } catch (e) {
      if (!mounted) return;
      _showError('Playback failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showCallUnavailable(String type) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$type call'),
        content: const Text(
          'Qivora stores messages locally and has no signaling server '
          'configured, so voice/video calls are not available in this build. '
          'A signaling server and WebRTC relay (STUN/TURN) are required for '
          'real calls.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Load reactions for all messages currently displayed.
  Future<Map<String, List<Map<String, dynamic>>>> _loadReactions() async {
    final db = await DatabaseService.instance.database;
    final messageIds = _msgs.map((m) => m['id'] as String).toSet().toList();
    if (messageIds.isEmpty) return {};
    final result = <String, List<Map<String, dynamic>>>{};
    for (final mid in messageIds) {
      final rows = await db.query(
        'message_reactions',
        where: 'message_id = ?',
        whereArgs: [mid],
      );
      result[mid] = rows;
    }
    return result;
  }

  /// Toggle a reaction on a message.
  Future<void> _toggleReaction(String messageId, String emoji) async {
    final db = await DatabaseService.instance.database;
    final existing = await db.query(
      'message_reactions',
      where: 'message_id = ? AND user_id = ?',
      whereArgs: [messageId, _currentUserId],
    );
    final now = DateTime.now().toIso8601String();
    if (existing.isNotEmpty) {
      final currentEmoji = existing.first['emoji'] as String?;
      if (currentEmoji == emoji) {
        await db.delete(
          'message_reactions',
          where: 'id = ?',
          whereArgs: [existing.first['id'] as String],
        );
      } else {
        await db.update(
          'message_reactions',
          {'emoji': emoji, 'created_at': now},
          where: 'id = ?',
          whereArgs: [existing.first['id'] as String],
        );
      }
    } else {
      await db.insert(
        'message_reactions',
        {
          'id': const Uuid().v4(),
          'message_id': messageId,
          'user_id': _currentUserId,
          'emoji': emoji,
          'created_at': now,
        },
      );
    }
    await _refreshMessages();
  }

  /// Toggle the starred flag on a message.
  Future<void> _toggleStar(String messageId, bool currentlyStarred) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'messages',
      {
        'starred': currentlyStarred ? 0 : 1,
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    await _refreshMessages();
  }

  /// Mark all messages in this conversation as read (read cursor).
  Future<void> _markConversationAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final sendReadReceipts = prefs.getBool('privacy_read_receipts') ?? true;
    if (!sendReadReceipts) return;
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toIso8601String();
    final unread = await db.query(
      'messages',
      where:
          'conversation_id = ? AND sender_id != ? AND deleted_at IS NULL AND delivery_status != ?',
      whereArgs: [widget.conversationId, _currentUserId, 'read'],
    );
    final batch = db.batch();
    for (final m in unread) {
      batch.insert(
        'message_read_receipts',
        {
          'id': const Uuid().v4(),
          'message_id': m['id'] as String,
          'user_id': _currentUserId,
          'read_at': now,
        },
      );
      batch.update(
        'messages',
        {'delivery_status': 'read', 'updated_at': now},
        where: 'id = ?',
        whereArgs: [m['id'] as String],
      );
    }
    await batch.commit(noResult: true);
    if (mounted) setState(() {});
  }

  /// Reload messages and reactions after a reaction/star change.
  Future<void> _refreshMessages() async {
    await _load();
    _reactionCache = await _loadReactions();
  }

  /// Build a reactions map keyed by emoji with counts, plus the user's reaction.
  Map<String, dynamic>? _reactionsForMessage(Map<String, dynamic> m) {
    final rows = _reactionCache[m['id'] as String];
    if (rows == null || rows.isEmpty) return null;
    final map = <String, int>{};
    String? userReaction;
    for (final r in rows) {
      final emoji = r['emoji'] as String;
      map[emoji] = (map[emoji] ?? 0) + 1;
      if (r['user_id'] as String == _currentUserId) {
        userReaction = emoji;
      }
    }
    return {'reactions': map, 'userReaction': userReaction};
  }

  /// Show an emoji reaction picker bottom sheet for a message.
  void _showReactionPicker(Map<String, dynamic> m) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '😎'];
    final currentReactions = _reactionCache[m['id'] as String] ?? [];
    final userEmoji = currentReactions.firstWhere(
      (r) => r['user_id'] == _currentUserId,
      orElse: () => <String, dynamic>{},
    )['emoji'] as String?;
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'React to message',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: emojis.map((emoji) {
              final isSelected = emoji == userEmoji;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _toggleReaction(m['id'] as String, emoji);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 4),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 20,
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _toggleArchive() async {
    final db = await DatabaseService.instance.database;
    final row = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [widget.conversationId],
    );
    if (row.isEmpty || !mounted) return;
    final isArchived = _getBool(row.first['archived']);
    await db.update(
      'conversations',
      {
        'archived': isArchived ? 0 : 1,
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [widget.conversationId],
    );
    if (!mounted) return;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            isArchived ? 'Conversation unarchived' : 'Conversation archived'),
      ),
    );
  }

  Future<void> _deleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation'),
        content: const Text(
          'This will delete the conversation and all its messages. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final db = await DatabaseService.instance.database;
      await db.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [widget.conversationId],
      );
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      _showError('Delete failed: $e');
    }
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text(
          'Delete this message for you? The message will be removed from '
          'this conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final db = await DatabaseService.instance.database;
      await db.update(
        'messages',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [messageId],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Delete failed: $e');
    }
  }

  Future<void> _editMessage(Map<String, dynamic> m) async {
    final isSent = (m['sender_id'] as String? ?? '') == _currentUserId;
    if (!isSent) return;
    final controller =
        TextEditingController(text: m['content'] as String? ?? '');
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == null || confirmed.isEmpty || !mounted) return;
    try {
      final db = await DatabaseService.instance.database;
      await db.update(
        'messages',
        {'content': confirmed, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND sender_id = ?',
        whereArgs: [m['id'] as String, _currentUserId],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Edit failed: $e');
    }
  }

  Future<void> _forwardMessage(Map<String, dynamic> m) async {
    final db = await DatabaseService.instance.database;
    final conversations = await db.query(
      'conversations',
      where: 'id != ? AND archived = 0',
      whereArgs: [widget.conversationId],
      orderBy: 'updated_at DESC',
    );
    if (conversations.isEmpty) {
      _showError('No other conversations to forward to.');
      return;
    }
    if (!mounted) return;
    final targetId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView.builder(
        shrinkWrap: true,
        itemCount: conversations.length,
        itemBuilder: (_, i) {
          final c = conversations[i];
          return ListTile(
            leading: QivoraAvatar(
              displayName: c['title'] as String? ?? 'Unknown',
              radius: 22,
              online: false,
              showOnlineIndicator: false,
            ),
            title: Text(c['title'] as String? ?? 'Unknown'),
            onTap: () => Navigator.pop(context, c['id'] as String),
          );
        },
      ),
    );
    if (targetId == null || !mounted) return;
    try {
      final now = DateTime.now().toIso8601String();
      final id = const Uuid().v4();
      await db.insert(
        'messages',
        {
          'id': id,
          'conversation_id': targetId,
          'sender_id': _currentUserId,
          'message_type': m['message_type'],
          'content': m['content'],
          'reply_to_message_id': null,
          'attachment_path': m['attachment_path'],
          'attachment_filename': m['attachment_filename'],
          'attachment_size': m['attachment_size'],
          'attachment_type': m['attachment_type'],
          'media_duration': m['media_duration'],
          'forwarded_from_message_id': m['id'],
          'forwarded_from_conversation_id': widget.conversationId,
          'delivery_status': 'sent',
          'created_at': now,
          'updated_at': now,
        },
      );
      await db.update(
        'conversations',
        {'last_message_id': id, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [targetId],
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Forward failed: $e');
    }
  }

  void _openMessageActions(Map<String, dynamic> m) {
    final isSent = (m['sender_id'] as String? ?? '') == _currentUserId;
    final content = m['content'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m['message_type'] == 'text')
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                _copyText(content);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_reaction),
            title: const Text('React'),
            onTap: () {
              Navigator.pop(context);
              _showReactionPicker(m);
            },
          ),
          ListTile(
            leading: Icon(
              _getBool(m['starred']) ? Icons.star : Icons.star_border,
              color: _getBool(m['starred']) ? AppColors.primary : null,
            ),
            title: Text(
              _getBool(m['starred']) ? 'Unstar' : 'Star',
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleStar(m['id'] as String, _getBool(m['starred']));
            },
          ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(context);
              _setReply(m['id'] as String, content);
            },
          ),
          if (isSent)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                _editMessage(m);
              },
            ),
          ListTile(
            leading: const Icon(Icons.forward),
            title: const Text('Forward'),
            onTap: () {
              Navigator.pop(context);
              _forwardMessage(m);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () {
              Navigator.pop(context);
              _deleteMessage(m['id'] as String);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> m) {
    final isSent = (m['sender_id'] as String? ?? '') == _currentUserId;
    final createdAt =
        DateTime.tryParse(m['created_at'] as String) ?? DateTime.now();
    bool showSeparator = true;
    final index = _msgs.indexWhere((mm) => mm['id'] == m['id']);
    if (index > 0) {
      final prev = DateTime.tryParse(_msgs[index - 1]['created_at'] as String);
      if (prev != null &&
          prev.year == createdAt.year &&
          prev.month == createdAt.month &&
          prev.day == createdAt.day) {
        showSeparator = false;
      }
    }

    String? replyPreview;
    final replyToId = m['reply_to_message_id'] as String?;
    if (replyToId != null) {
      final original = _msgs.firstWhere(
        (mm) => mm['id'] == replyToId,
        orElse: () => <String, dynamic>{},
      );
      if (original.isNotEmpty) {
        final orig = (original['content'] as String? ?? '');
        replyPreview =
            (orig.length > 40 ? '${orig.substring(0, 40)}...' : orig);
      }
    }
    final reactionInfo = _reactionsForMessage(m);
    final messageWidget = m['message_type'] == 'image' ||
            m['message_type'] == 'file' ||
            m['message_type'] == 'audio'
        ? _AttachmentMessage(
            message: m,
            isSent: isSent,
            createdAt: createdAt,
            showSeparator: showSeparator,
            onPlayAudio: m['message_type'] == 'audio'
                ? () => _toggleVoicePlayback(
                      m['id'] as String,
                      m['audio_path'] as String? ?? '',
                    )
                : null,
          )
        : QivoraMessageBubble(
            key: ValueKey('msg-${m['id']}'),
            text: m['content'] as String? ?? '',
            isSent: isSent,
            createdAt: createdAt,
            deliveryStatus:
                isSent ? _status(m['delivery_status'] as String?) : null,
            showDateSeparator: showSeparator,
            replyToText: replyPreview,
            isForwarded: _getBool(m['forwarded_from_message_id'] != null),
            reactions: reactionInfo?['reactions'] as Map<String, int>?,
            userReaction: reactionInfo?['userReaction'] as String?,
          );
    return GestureDetector(
      onLongPress: () => _openMessageActions(m),
      child: messageWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.conversationTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: QivoraAvatar(
          displayName: widget.conversationTitle,
          radius: 20,
          online: false,
          showOnlineIndicator: false,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _showCallUnavailable('Video'),
            tooltip: 'Video call',
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _showCallUnavailable('Voice'),
            tooltip: 'Voice call',
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Conversation actions',
            onSelected: (item) async {
              switch (item) {
                case 0:
                  await _toggleArchive();
                  break;
                case 1:
                  await _deleteConversation();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 0,
                child: Text('Archive conversation'),
              ),
              const PopupMenuItem(
                value: 1,
                child: Text('Delete conversation',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!_loading && !_loadingMore && _msgs.isNotEmpty) {
            final metrics = notification.metrics;
            if (metrics.atEdge && metrics.pixels <= 0) {
              _loadOlder();
            }
          }
          return false;
        },
        child: _loading
            ? const Center(
                child: Text('Loading messages…'),
              )
            : _error != null && _msgs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load messages',
                          style: TextStyle(
                            color: isDark ? Colors.white : AppColors.textMain,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _msgs.isEmpty
                    ? const Center(
                        child: Text('No messages yet'),
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.all(12),
                              itemCount: _msgs.length,
                              itemBuilder: (_, i) => _buildMessage(_msgs[i]),
                            ),
                          ),
                          if (_isRecording)
                            Container(
                              color: AppColors.error.withValues(alpha: 0.1),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.mic, color: AppColors.error),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Recording: ${_recordDuration.inMinutes.toString().padLeft(2, '0')}:${_recordDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  IconButton(
                                    icon: const Icon(Icons.stop,
                                        color: AppColors.error),
                                    onPressed: _stopVoiceRecording,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.cancel,
                                        color: AppColors.error),
                                    onPressed: _cancelVoiceRecording,
                                  ),
                                ],
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          _buildInput(context),
                        ],
                      ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        color: isDark ? AppColors.darkSurface : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToId != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to: $_replyToText',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.primary,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _setReply(null, null),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 18, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 24),
                  onPressed: _sending ? null : _showAttachSheet,
                  tooltip: 'Attach',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    enabled: !_sending,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : AppColors.textSecondary,
                        fontSize: 15,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2D3748)
                          : AppColors.bubbleSent.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: _sending ? null : _send,
                    tooltip: 'Send',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('Choose image'),
            onTap: () {
              Navigator.pop(context);
              _attachImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take photo'),
            onTap: () {
              Navigator.pop(context);
              _attachImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: const Text('Choose file'),
            onTap: () {
              Navigator.pop(context);
              _attachFile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Record voice message'),
            onTap: () {
              Navigator.pop(context);
              if (_isRecording) {
                _stopVoiceRecording();
              } else {
                _startVoiceRecording();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onDraftChanged);
    _ctrl.dispose();
    _scroll.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

/// Renders image, file, and audio attachments within a message bubble row.
class _AttachmentMessage extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isSent;
  final DateTime createdAt;
  final bool showSeparator;
  final VoidCallback? onPlayAudio;

  const _AttachmentMessage({
    required this.message,
    required this.isSent,
    required this.createdAt,
    this.showSeparator = false,
    this.onPlayAudio,
  });

  Future<void> _preview(BuildContext context) async {
    final path = message['attachment_path'] as String? ?? '';
    if (path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message['message_type'] == 'image')
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
              )
            else
              ListTile(
                leading: const Icon(
                  Icons.insert_drive_file,
                  size: 48,
                  color: AppColors.primary,
                ),
                title:
                    Text(message['attachment_filename'] as String? ?? 'File'),
                subtitle: Text(
                  'Tap to open the attachment in Files.',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF94A3B8)
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final path = message['attachment_path'] as String? ?? '';
    final exists = path.isNotEmpty ? File(path).existsSync() : false;
    final time = DateFormat('hh:mm a').format(createdAt);

    Widget bubbleContent;
    if (message['message_type'] == 'image' && exists) {
      bubbleContent = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: 220,
          height: 160,
          fit: BoxFit.cover,
        ),
      );
    } else if (message['message_type'] == 'audio') {
      bubbleContent = Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.play_arrow,
                size: 20,
              ),
              color: AppColors.primary,
              onPressed: onPlayAudio,
            ),
            Text(
              '${(message['media_duration'] as int? ?? 0) ~/ 1024} KB',
              style: TextStyle(
                fontSize: 11,
                color:
                    isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    } else {
      bubbleContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            message['message_type'] == 'image'
                ? Icons.broken_image
                : Icons.insert_drive_file,
            color: isSent ? Colors.white : AppColors.textMain,
            size: 32,
          ),
          const SizedBox(height: 6),
          Text(
            message['attachment_filename'] as String? ?? 'Attachment',
            style: TextStyle(
              color: isSent ? Colors.white : AppColors.textMain,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(message['attachment_size'] as int? ?? 0) ~/ 1024} KB',
            style: TextStyle(
              color: isSent ? Colors.white70 : AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          if (!exists)
            const Text(
              'File no longer available',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showSeparator)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D3748) : AppColors.divider,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  DateFormat('MMM d, yyyy').format(createdAt),
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: exists && message['message_type'] == 'image'
              ? () => _preview(context)
              : null,
          child: Column(
            crossAxisAlignment:
                isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSent
                      ? (isDark
                          ? const Color(0xFF0E7C61)
                          : AppColors.bubbleSent)
                      : (isDark
                          ? AppColors.darkBubbleReceived
                          : AppColors.bubbleReceived),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: bubbleContent,
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: isSent ? 0 : 6,
                  right: isSent ? 6 : 0,
                  top: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (isSent) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.done_rounded,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

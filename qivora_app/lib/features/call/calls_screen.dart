import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/database_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/qivora_empty_state.dart';

/// Calls screen showing real call history from SQLite.
///
/// Call records are only written by [CallRepository] when a call actually
/// occurs; this screen simply displays them. No fake call entries are shown.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  List<Map<String, dynamic>> _calls = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.rawQuery('''
        SELECT ch.*, c.title AS conversation_title
        FROM call_history ch
        LEFT JOIN conversations c ON c.id = ch.conversation_id
        ORDER BY ch.start_time DESC
      ''');
      if (mounted) {
        setState(() {
          _calls = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return DateFormat('hh:mm a').format(dt);
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    return DateFormat('MMM d').format(dt);
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const QivoraLoading(message: 'Loading call history…')
          : _calls.isEmpty
              ? const QivoraEmptyState(
                  icon: Icons.call_outlined,
                  title: 'No call history',
                  subtitle: 'Your calls will appear here.',
                  action: null,
                )
              : ListView.builder(
                  itemCount: _calls.length,
                  itemBuilder: (_, i) {
                    final c = _calls[i];
                    final callType = c['call_type'] as String? ?? 'voice';
                    final status = c['call_status'] as String? ?? 'unknown';
                    final startTime = c['start_time'] as String?;
                    final durationMs = c['duration'] as int?;
                    final title =
                        c['conversation_title'] as String? ?? 'Unknown';
                    final isOutgoing =
                        (c['caller_id'] as String? ?? '') == 'me';

                    IconData icon;
                    Color iconColor;
                    if (callType == 'video') {
                      icon = Icons.videocam;
                      iconColor = AppColors.primary;
                    } else {
                      icon = Icons.call;
                      iconColor = isDark
                          ? const Color(0xFF94A3B8)
                          : AppColors.textSecondary;
                    }

                    Color statusColor;
                    switch (status) {
                      case 'connected':
                        statusColor = AppColors.online;
                      case 'missed':
                      case 'rejected':
                      case 'failed':
                      case 'timedOut':
                        statusColor = AppColors.error;
                      default:
                        statusColor = AppColors.textSecondary;
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: iconColor.withValues(alpha: 0.15),
                        child: Icon(
                          icon,
                          color: iconColor,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          color: isDark ? Colors.white : AppColors.textMain,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${isOutgoing ? 'Outgoing' : 'Incoming'} • $callType call',
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (durationMs != null) ...[
                                const SizedBox(width: 12),
                                Text(
                                  _formatDuration(
                                    Duration(milliseconds: durationMs),
                                  ),
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTime(startTime != null
                                ? DateTime.tryParse(startTime)
                                : null),
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(title),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${isOutgoing ? 'Outgoing' : 'Incoming'} • $callType call',
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Status: $status',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (durationMs != null)
                                  Text(
                                    'Duration: ${_formatDuration(Duration(milliseconds: durationMs))}',
                                  ),
                                Text(
                                  _formatTime(startTime != null
                                      ? DateTime.tryParse(startTime)
                                      : null),
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/contacts'),
        child: const Icon(Icons.call_rounded),
      ),
    );
  }
}

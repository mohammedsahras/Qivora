import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

/// Delivery status of a message.
enum MessageDeliveryStatus { sent, delivered, read }

/// A single message bubble with timestamp and optional delivery status.
///
/// [isSent] determines alignment and bubble colour. [deliveryStatus] is only
/// shown for sent messages and is never faked — it reflects the value stored
/// in the database. [replyToText], when provided, shows a small reply preview
/// above the message. [isForwarded] marks forwarded messages.
/// [reactions] is a map of emoji -> count, shown under the message.
/// [userReaction] is the emoji the current user has reacted with (if any).
class QivoraMessageBubble extends StatelessWidget {
  final String text;
  final bool isSent;
  final DateTime createdAt;
  final MessageDeliveryStatus? deliveryStatus;
  final bool showDateSeparator;
  final String? replyToText;
  final bool isForwarded;
  final Map<String, int>? reactions;
  final String? userReaction;

  const QivoraMessageBubble({
    super.key,
    required this.text,
    required this.isSent,
    required this.createdAt,
    this.deliveryStatus,
    this.showDateSeparator = false,
    this.replyToText,
    this.isForwarded = false,
    this.reactions,
    this.userReaction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final time = DateFormat('hh:mm a').format(createdAt);

    Widget statusIcon;
    switch (deliveryStatus) {
      case MessageDeliveryStatus.read:
        statusIcon = const Icon(
          Icons.done_all_rounded,
          size: 14,
          color: AppColors.primary,
        );
      case MessageDeliveryStatus.delivered:
        statusIcon = const Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Color(0xFF94A3B8),
        );
      case MessageDeliveryStatus.sent:
      case null:
        statusIcon = const Icon(
          Icons.done_rounded,
          size: 14,
          color: Color(0xFF94A3B8),
        );
    }

    final bubbleColor = isSent
        ? (isDark ? const Color(0xFF0E7C61) : AppColors.bubbleSent)
        : (isDark ? AppColors.darkBubbleReceived : AppColors.bubbleReceived);
    final textColor = isSent
        ? (isDark ? Colors.white : AppColors.textMain)
        : (isDark ? Colors.white : AppColors.textMain);

    final children = <Widget>[
      if (showDateSeparator) _DateSeparator(date: createdAt),
      if (replyToText != null && replyToText!.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (isSent ? AppColors.primary : AppColors.secondary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isSent ? AppColors.primary : AppColors.secondary)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to',
                  style: TextStyle(
                    color: (isSent ? AppColors.primary : AppColors.secondary),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyToText!,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textMain,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      if (reactions != null && reactions!.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _ReactionsRow(
            reactions: reactions!,
            userReaction: userReaction,
            isSent: isSent,
          ),
        ),
      ],
      Column(
        crossAxisAlignment:
            isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
              ),
            ),
            if (isForwarded)
              Padding(
                padding: EdgeInsets.only(
                  left: isSent ? 0 : 6,
                  right: isSent ? 6 : 0,
                  top: 2,
                ),
                child: Text(
                  'Forwarded',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
    ];

    if (isSent) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 2),
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
              const SizedBox(width: 4),
              statusIcon,
            ],
          ),
        ),
      );
    } else {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 2),
          child: Text(
            time,
            style: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// A thin date separator shown between messages on different days.
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = DateFormat('MMM d, yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D3748) : AppColors.divider,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of reaction emoji with counts, shown under a message.
class _ReactionsRow extends StatelessWidget {
  final Map<String, int> reactions;
  final String? userReaction;
  final bool isSent;

  const _ReactionsRow({
    required this.reactions,
    this.userReaction,
    required this.isSent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: reactions.entries.map((entry) {
        final emoji = entry.key;
        final count = entry.value;
        final isMine = emoji == userReaction;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (isMine ? AppColors.primary : AppColors.secondary)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (isMine ? AppColors.primary : AppColors.secondary)
                  .withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isMine
                      ? AppColors.primary
                      : (isDark ? Colors.white : AppColors.textMain),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

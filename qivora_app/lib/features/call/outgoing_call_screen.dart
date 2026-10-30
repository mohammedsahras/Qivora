import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qivora_app/core/services/call_signaling_service.dart';
import 'package:qivora_app/core/theme/app_colors.dart';
import 'package:qivora_app/core/theme/app_theme.dart';

import '../../core/providers/call_state_provider.dart';

/// Screen shown when initiating an outbound call.
/// Displays calling status and options to cancel.
class OutgoingCallScreen extends ConsumerWidget {
  final String recipientName;
  final String callId;
  final String callType; // 'voice' or 'video'
  final String? conversationId;

  const OutgoingCallScreen({
    super.key,
    required this.recipientName,
    required this.callId,
    required this.callType,
    this.conversationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callStateProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.of(context).isDark
            ? AppColors.darkSurface
            : AppColors.lightBackground,
        title: Text(callType == 'video' ? 'Video Call' : 'Voice Call'),
      ),
      body: Center(
        child: Material(
          color: AppTheme.of(context).isDark
              ? AppColors.darkSurface
              : AppColors.lightBackground,
          borderRadius: BorderRadius.circular(20),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Call type icon
                Icon(
                  callType == 'video' ? Icons.video_call : Icons.call,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                // Recipient info
                Text(
                  'Calling $recipientName',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Conversation info if applicable
                if (conversationId != null)
                  Text(
                    'Conversation: $conversationId',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                // Status and controls
                Text(
                  callState.status == CallStatus.initiating
                      ? 'Calling...'
                      : callState.status == CallStatus.ringing
                          ? 'Ringing...'
                          : 'Connected',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                // Cancel button
                ElevatedButton(
                  onPressed: () {
                    // Signal call cancellation
                    CallSignalingService.instance.rejectCall();
                    ref
                        .read(callStateProvider.notifier)
                        .setStatus(CallStatus.rejected);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 40),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

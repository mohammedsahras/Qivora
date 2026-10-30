import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qivora_app/core/services/call_signaling_service.dart';
import 'package:qivora_app/core/services/webrtc_service.dart';
import 'package:qivora_app/core/theme/app_colors.dart';
import 'package:qivora_app/core/theme/app_theme.dart';

import '../../core/providers/call_state_provider.dart';

/// Screen shown when an incoming call is received.
/// Displays caller info and Accept/Reject buttons.
class IncomingCallScreen extends ConsumerWidget {
  final String callerName;
  final String callId;
  final String callType; // 'voice' or 'video'
  final String? conversationId;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.callId,
    required this.callType,
    this.conversationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final webRTC = WebRTCService.instance;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
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
                // Caller info
                Text(
                  'Calling from $callerName',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Conversation info if group call
                if (conversationId != null)
                  Text(
                    'Conversation: $conversationId',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Reject button
                    ElevatedButton(
                      onPressed: () {
                        // Signal call rejection
                        CallSignalingService.instance.rejectCall();
                        // Update call state
                        ref
                            .read(callStateProvider.notifier)
                            .setStatus(CallStatus.rejected);
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 40),
                      ),
                      child: const Text('Reject'),
                    ),
                    const SizedBox(width: 16),
                    // Accept button
                    ElevatedButton(
                      onPressed: () {
                        // Accept the call and start WebRTC
                        CallSignalingService.instance.acceptCall();
                        ref
                            .read(callStateProvider.notifier)
                            .setStatus(CallStatus.connecting);
                        // Initialize WebRTC
                        webRTC.initialize();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(100, 40),
                      ),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

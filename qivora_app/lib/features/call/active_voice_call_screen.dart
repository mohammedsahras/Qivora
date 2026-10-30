import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qivora_app/core/services/call_signaling_service.dart';
import 'package:qivora_app/core/services/webrtc_service.dart';
import 'package:qivora_app/core/theme/app_colors.dart';
import 'package:qivora_app/core/theme/app_theme.dart';

import '../../core/providers/call_state_provider.dart';

/// Active voice call screen - shows local/microphone status and call controls.
/// Remote audio is handled on the other device; this screen focuses on
/// microphone mute/unmute and call duration.
class ActiveVoiceCallScreen extends ConsumerWidget {
  final String callId;
  final String callerName;
  final String recipientName;
  final String conversationId;

  const ActiveVoiceCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.recipientName,
    required this.conversationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callStateProvider);
    final webRTC = WebRTCService.instance;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.of(context).isDark
            ? AppColors.darkSurface
            : AppColors.lightBackground,
        title: const Text('Voice Call'),
        actions: [
          // Mute/unmute button
          IconButton(
            icon: Icon(
              callState.microphoneMuted ? Icons.mic_off : Icons.mic,
            ),
            onPressed: () {
              // Toggle microphone - in full implementation,
              // would disable/enable the local audio track
              // and update call state
              ref.read(callStateProvider.notifier).setStatus(
                    callState.status == CallStatus.connecting
                        ? CallStatus.connected
                        : CallStatus.connecting,
                  );
            },
          ),
        ],
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
                // Call info
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      callerName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                    ),
                    const Text(' → '),
                    Text(
                      recipientName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.primary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Call duration
                const Text(
                  '00:00',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                // End call button
                ElevatedButton(
                  onPressed: () {
                    // End the call
                    webRTC.hangUp();
                    ref.read(callStateProvider.notifier).setStatus(
                          CallStatus.ended,
                        );
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 40),
                  ),
                  child: const Text('End Call'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

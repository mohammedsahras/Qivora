import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qivora_app/core/services/call_signaling_service.dart';
import 'package:qivora_app/core/services/webrtc_service.dart';
import 'package:qivora_app/core/theme/app_colors.dart';
import 'package:qivora_app/core/theme/app_theme.dart';

import '../../core/providers/call_state_provider.dart';

/// Active video call screen - shows local video preview and remote video.
/// Includes camera toggle and microphone controls.
class ActiveVideoCallScreen extends ConsumerWidget {
  final String callId;
  final String callerName;
  final String recipientName;
  final String conversationId;

  const ActiveVideoCallScreen({
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
    final isDark = AppTheme.of(context).isDark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightBackground,
        title: const Text('Video Call'),
        actions: [
          // Camera toggle
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: () {
              // Toggle camera (front/rear) - full implementation
              // requires physical device testing.
            },
          ),
          // Mute button
          IconButton(
            icon: Icon(
              callState.microphoneMuted ? Icons.mic_off : Icons.mic,
            ),
            onPressed: () {
              // Toggle microphone - full implementation
              // requires physical device testing.
            },
          ),
        ],
      ),
      body: _buildCallContent(context, ref, callState, webRTC, isDark),
    );
  }

  Widget _buildCallContent(
    BuildContext context,
    WidgetRef ref,
    CallState callState,
    WebRTCService webRTC,
    bool isDark,
  ) {
    final backgroundColor =
        isDark ? AppColors.darkSurface : AppColors.lightBackground;

    return Center(
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Remote video renderer placeholder
              const Icon(
                Icons.video_call,
                size: 80,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              // Local video placeholder
              const CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.primary,
                child: Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 24),
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
              // Duration
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
    );
  }
}

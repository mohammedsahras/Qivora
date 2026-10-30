import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qivora_app/core/services/call_signaling_service.dart';

final callStateProvider =
    StateNotifierProvider<CallStateNotifier, CallState>((ref) {
  return CallStateNotifier();
});

/// Riverpod notifier that manages the call state machine.
class CallStateNotifier extends StateNotifier<CallState> {
  CallStateNotifier() : super(CallState(callId: '', callerId: '')) {
    _initSignaling();
  }

  /// The underlying signaling service (singleton).
  final CallSignalingService _signalingService = CallSignalingService.instance;

  /// Current call status, delegated to the underlying [CallState].
  CallStatus get status => state.status;

  /// Update the call status and notify listeners.
  void setStatus(CallStatus newStatus) {
    state = state..status = newStatus;
  }

  /// Initialize signaling and bind to UI lifecycle.
  Future<void> _initSignaling() async {
    // TODO: replace with actual signaling server URI from config
    const uri = 'ws://localhost:8080';
    await _signalingService.connect(
      serverUri: uri,
      userId: '', // TODO: fetch from auth session
    );
  }

  /// [recipientId] is the user or group this call is for.
  /// [conversationId] is the conversation context.
  /// [callType] is 'voice' or 'video'.
  Future<void> initiateCall({
    required String recipientId,
    required String conversationId,
    required String callType,
  }) async {
    await _signalingService.initiateCall(
      recipientId: recipientId,
      conversationId: conversationId,
      callType: callType,
    );
    // Update local state to match signaling service state
    state = _signalingService.state;
  }

  /// Accept an incoming call.
  Future<void> acceptCall() async {
    await _signalingService.acceptCall();
    // Update state to connecting
    state = CallState(
      callId: state.callId,
      callerId: state.callerId,
      recipientId: state.recipientId,
      conversationId: state.conversationId,
      callType: state.callType,
    )..status = CallStatus.connecting;
  }

  /// Reject an incoming call.
  Future<void> rejectCall() async {
    await _signalingService.rejectCall();
    state = CallState(
      callId: state.callId,
      callerId: state.callerId,
      recipientId: state.recipientId,
      conversationId: state.conversationId,
      callType: state.callType,
    )..status = CallStatus.rejected;
  }

  /// End the active call.
  Future<void> endCall() async {
    await _signalingService.endCall();
    state = CallState(callId: '', callerId: '');
  }

  /// Send an ICE candidate to the remote peer.
  Future<void> sendIceCandidate(Map<String, dynamic> candidate) async {
    await _signalingService.sendIceCandidate(candidate);
  }

  /// Client-side call timeout.
  Future<void> timeoutCall() async {
    await _signalingService.timeoutCall();
    state = CallState(callId: '', callerId: '');
  }

  /// Dispose of the signaling connection.
  @override
  void dispose() {
    _signalingService.dispose();
    super.dispose();
  }
}

import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

/// JSON schema for each call signaling event.
class CallSignalingEvent {
  final String type;
  final String callId;
  final String senderId;
  final String? recipientId;
  final String? conversationId;
  final String? callType;
  final Map<String, dynamic>? payload;

  CallSignalingEvent({
    required this.type,
    required this.callId,
    required this.senderId,
    this.recipientId,
    this.conversationId,
    this.callType,
    this.payload,
  });

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> data = {
      'type': type,
      'callId': callId,
      'senderId': senderId,
    };
    if (recipientId != null) data['recipientId'] = recipientId;
    if (conversationId != null) data['conversationId'] = conversationId;
    if (callType != null) data['callType'] = callType;
    if (payload != null) data['payload'] = payload;
    return data;
  }

  factory CallSignalingEvent.fromMap(Map<String, dynamic> map) {
    return CallSignalingEvent(
      type: map['type'] as String,
      callId: map['callId'] as String,
      senderId: map['senderId'] as String,
      recipientId: map['recipientId'] as String?,
      conversationId: map['conversationId'] as String?,
      callType: map['callType'] as String?,
      payload:
          (map['payload'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
    );
  }
}

enum CallEventType {
  initiate,
  ring,
  accept,
  reject,
  cancel,
  offer,
  answer,
  iceCandidate,
  end,
  timeout,
  error,
}

/// Minimal call state — no copyWith, direct assignment only.
class CallState {
  final String callId;
  final String callerId;
  final String? recipientId;
  final String? conversationId;
  final String callType;
  CallEventType? event;
  CallStatus status;
  bool microphoneMuted = false;
  DateTime? startedAt;
  DateTime? endedAt;
  Duration? duration;

  CallState({
    required this.callId,
    required this.callerId,
    this.recipientId,
    this.conversationId = '',
    this.callType = 'voice',
  })  : status = CallStatus.idle,
        startedAt = null,
        endedAt = null,
        duration = null;

  CallState copyWithStatus(CallStatus newStatus,
      {CallEventType? event, Map<String, dynamic>? payload}) {
    final s = CallState(
      callId: callId,
      callerId: callerId,
      recipientId: recipientId,
      conversationId: conversationId,
      callType: callType,
    )..status = newStatus;
    s.event = event ?? this.event;
    s.microphoneMuted = microphoneMuted;
    return s;
  }
}

enum CallStatus {
  idle,
  initiating,
  ringing,
  connecting,
  connected,
  reconnecting,
  rejected,
  ended,
  failed,
  timedOut,
}

/// Lightweight signaling service (WebSocket event routing only).
/// Does NOT persist media streams or offer/answer payloads beyond what is
/// needed for state transitions. Callers must run WebRTC separately.
class CallSignalingService {
  CallSignalingService._();
  static final CallSignalingService instance = CallSignalingService._();

  /// [WebSocket] channel connected to the signaling server.
  WebSocketChannel? _channel;

  CallState _state = CallState(callId: '', callerId: '');

  CallState get state => _state;

  Future<void> connect({
    required String serverUri,
    required String userId,
  }) async {
    _channel = WebSocketChannel.connect(Uri.parse(serverUri));
    _channel!.stream.listen(_onMessage);
  }

  void _onMessage(dynamic raw) {
    String? text;
    if (raw is String) {
      text = raw;
    } else if (raw is Map<String, dynamic>) {
      text = json.encode(raw);
    }
    if (text == null) return;

    Map<String, dynamic>? map;
    try {
      map = json.decode(text) as Map<String, dynamic>?;
    } catch (_) {
      return;
    }
    if (map == null) return;

    final ev = CallSignalingEvent.fromMap(map);
    _dispatch(ev);
  }

  void _dispatch(CallSignalingEvent ev) {
    switch (ev.type) {
      case 'call.initiate':
        _state = _state.copyWithStatus(CallStatus.initiating);
        break;
      case 'call.ring':
        _state = _state.copyWithStatus(CallStatus.ringing);
        break;
      case 'call.accept':
        _state = _state.copyWithStatus(CallStatus.connecting);
        break;
      case 'call.reject':
        _state = _state.copyWithStatus(CallStatus.rejected);
        break;
      case 'call.cancel':
        _state = _state.copyWithStatus(CallStatus.ended);
        break;
      case 'call.offer':
        _state =
            _state.copyWithStatus(_state.status, event: CallEventType.offer);
        break;
      case 'call.answer':
        _state =
            _state.copyWithStatus(_state.status, event: CallEventType.answer);
        break;
      case 'call.ice_candidate':
        // payload handled externally (WebRTC)
        break;
      case 'call.end':
        _state = CallState(
          callId: _state.callId,
          callerId: _state.callerId,
          recipientId: _state.recipientId,
          conversationId: _state.conversationId,
          callType: _state.callType,
        )..status = CallStatus.ended;
        break;
      case 'call.timeout':
        _state = _state.copyWithStatus(CallStatus.timedOut);
        break;
      case 'call.error':
        _state = _state.copyWithStatus(CallStatus.failed);
        break;
    }
  }

  Future<void> initiateCall({
    required String recipientId,
    required String conversationId,
    required String callType,
  }) async {
    final String callId = const Uuid().v4();
    final ev = CallSignalingEvent(
      type: 'call.initiate',
      callId: callId,
      senderId: '',
      recipientId: recipientId,
      conversationId: conversationId,
      callType: callType,
    );
    _channel?.sink.add(ev.toMap());
    _state = CallState(
      callId: callId,
      callerId: '',
      recipientId: recipientId,
      conversationId: conversationId,
      callType: callType,
    )..status = CallStatus.initiating;
  }

  Future<void> acceptCall() async {
    if (_state.callId.isEmpty) return;
    final ev = CallSignalingEvent(
        type: 'call.accept', callId: _state.callId, senderId: '');
    _channel?.sink.add(ev.toMap());
    _state = _state.copyWithStatus(CallStatus.connecting);
  }

  Future<void> rejectCall() async {
    if (_state.callId.isEmpty) return;
    final ev = CallSignalingEvent(
        type: 'call.reject', callId: _state.callId, senderId: '');
    _channel?.sink.add(ev.toMap());
    _state = _state.copyWithStatus(CallStatus.rejected);
  }

  Future<void> endCall() async {
    if (_state.callId.isEmpty) return;
    final ev = CallSignalingEvent(
        type: 'call.end', callId: _state.callId, senderId: '');
    _channel?.sink.add(ev.toMap());
    _state = CallState(
      callId: _state.callId,
      callerId: _state.callerId,
      recipientId: _state.recipientId,
      conversationId: _state.conversationId,
      callType: _state.callType,
    )..status = CallStatus.ended;
  }

  Future<void> sendIceCandidate(Map<String, dynamic> candidate) async {
    if (_state.callId.isEmpty) return;
    final ev = CallSignalingEvent(
      type: 'call.ice_candidate',
      callId: _state.callId,
      senderId: '',
      payload: candidate,
    );
    _channel?.sink.add(ev.toMap());
  }

  Future<void> timeoutCall() async {
    if (_state.callId.isEmpty) return;
    final ev = CallSignalingEvent(
        type: 'call.timeout', callId: _state.callId, senderId: '');
    _channel?.sink.add(ev.toMap());
    _state = _state.copyWithStatus(CallStatus.timedOut);
  }

  void dispose() {
    _channel?.sink.close();
    _channel = null;
    _state = CallState(callId: '', callerId: '');
  }
}

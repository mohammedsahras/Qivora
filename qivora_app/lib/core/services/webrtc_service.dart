import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import './call_signaling_service.dart';
import '../providers/call_state_provider.dart';

/// WebRTC service handles peer-to-peer media connections.
/// Uses the existing Phase 5A WebSocket signaling for setup only.
/// Media streams are transported directly between peers via WebRTC.
/// NOTE: This service requires physical device testing with STUN/TURN
/// configuration to verify actual audio/video connectivity.
class WebRTCService {
  WebRTCService._() : _callState = CallStateNotifier();
  static final WebRTCService instance = WebRTCService._();

  /// Peer connection from flutter_webrtc (created via the factory, since
  /// [RTCPeerConnection] is abstract).
  RTCPeerConnection? _peerConnection;

  /// Local media stream (W3C MediaStream from flutter_webrtc)
  MediaStream? _localStream;

  /// Remote media stream from the peer
  MediaStream? _remoteStream;

  /// Last remote session description (offer/answer) received via signaling.
  RTCSessionDescription? _remoteDescription;

  /// Call state notifier (Riverpod-backed).
  final CallStateNotifier _callState;

  /// Whether the peer connection has already been created. Guards against
  /// duplicate initialization and the listener/resource leaks it causes.
  bool _created = false;

  /// Stream controllers for events
  final _onPeerConnectionStateChanged =
      StreamController<RTCIceConnectionState>.broadcast();
  final _onLocalStream = StreamController<MediaStream>.broadcast();
  final _onRemoteStream = StreamController<MediaStream>.broadcast();
  final _onError = StreamController<String>.broadcast();

  /// Get streams
  Stream<RTCIceConnectionState> get onPeerConnectionStateChanged =>
      _onPeerConnectionStateChanged.stream;
  Stream<MediaStream> get onLocalStream => _onLocalStream.stream;
  Stream<MediaStream> get onRemoteStream => _onRemoteStream.stream;
  Stream<String> get onError => _onError.stream;

  /// Last remote session description (offer/answer) received via signaling.
  RTCSessionDescription? get remoteDescription => _remoteDescription;

  /// Current call status, delegated to the call state notifier.
  CallStatus get callStatus => _callState.status;

  /// Initialize WebRTC (platform permissions are handled by the caller;
  /// this is a no-op scaffold kept for lifecycle compatibility).
  Future<void> initialize() async {
    // Permission handling is platform-specific and requires
    // physical device testing. See Phase 5B requirements.
  }

  /// Create a peer connection with ICE server configuration.
  /// Uses flutter_webrtc 1.6.3 [RTCFactory.createPeerConnection] because
  /// [RTCPeerConnection] is abstract and cannot be instantiated directly.
  Future<void> createPeerConnection() async {
    if (_created || _peerConnection != null) return;
    _created = true;

    final iceServers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ];

    _peerConnection = await RTCFactoryNative.instance.createPeerConnection({
      'iceServers': iceServers,
    });

    // Listen for ICE connection state changes via onIceConnectionState callback
    _peerConnection!.onIceConnectionState = (state) {
      _onPeerConnectionStateChanged.add(state);
      _handleIceStateChange(state);
    };

    // Listen for ICE candidates via onIceCandidate callback and signal them
    // to the remote peer through the existing WebSocket signaling service.
    _peerConnection!.onIceCandidate = (candidate) {
      _signalIceCandidate(candidate);
    };

    // Listen for the remote media stream. flutter_webrtc 1.6.3 (native)
    // delivers the remote stream via [RTCPeerConnection.onAddStream], and
    // unified-plan deliveries via [RTCPeerConnection.onTrack]. Handle both,
    // guarding against duplicate emissions.
    _peerConnection!.onAddStream = (stream) {
      if (_remoteStream == null) {
        _remoteStream = stream;
        _onRemoteStream.add(stream);
      }
    };

    _peerConnection!.onTrack = (event) {
      if (_remoteStream == null && event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _onRemoteStream.add(event.streams.first);
      }
    };
  }

  /// Add the local media stream (camera + microphone tracks) to the peer
  /// connection and expose it locally.
  Future<void> addLocalStream(MediaStream stream) async {
    _localStream = stream;
    _onLocalStream.add(stream);
    if (_peerConnection == null) return;
    for (final track in stream.getTracks()) {
      await _peerConnection!.addTrack(track, stream);
    }
  }

  /// Set the remote media stream manually (used when signaling delivers it
  /// out of band).
  void addRemoteStream(MediaStream stream) {
    _remoteStream = stream;
    _onRemoteStream.add(stream);
  }

  /// Handle ICE connection state changes and propagate call status.
  void _handleIceStateChange(RTCIceConnectionState state) {
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        _callState.setStatus(CallStatus.connected);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _callState.setStatus(CallStatus.reconnecting);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _callState.setStatus(CallStatus.failed);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        _callState.setStatus(CallStatus.ended);
        break;
      default:
        // New, checking, completed, count — no status transition.
        break;
    }
  }

  /// Signal an ICE candidate to the remote peer via WebSocket signaling.
  void _signalIceCandidate(RTCIceCandidate candidate) {
    CallSignalingService.instance.sendIceCandidate(candidate.toMap());
  }

  /// Create an SDP offer and set it as the local description.
  Future<void> createAndSetLocalOffer() async {
    if (_peerConnection == null) return;
    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
    } catch (e) {
      _onError.add(e.toString());
    }
  }

  /// Create an SDP answer and set it as the local description.
  Future<void> createAndSetLocalAnswer() async {
    if (_peerConnection == null) return;
    try {
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
    } catch (e) {
      _onError.add(e.toString());
    }
  }

  /// Set the remote session description (offer or answer from the peer).
  Future<void> setRemoteDescription(String sdp,
      {String type = 'answer'}) async {
    if (_peerConnection == null) return;
    try {
      // RTCServiceDescription constructor is RTCSessionDescription(sdp, type).
      final desc = RTCSessionDescription(sdp, type);
      _remoteDescription = desc;
      await _peerConnection!.setRemoteDescription(desc);
    } catch (e) {
      _onError.add(e.toString());
    }
  }

  /// Add an ICE candidate received from the remote peer.
  Future<void> addRemoteCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;
    try {
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      _onError.add(e.toString());
    }
  }

  /// Render local video to a widget.
  void setLocalRenderer(RTCVideoRenderer renderer) {
    // Connect the renderer to the local video track when a local stream
    // is available. Requires physical device testing.
    // The renderer is bound to the track by the consuming UI layer.
  }

  /// Render remote video to a widget.
  void setRemoteRenderer(RTCVideoRenderer renderer) {
    // Connect the renderer to the remote video track. Requires physical
    // device testing.
    // The renderer is bound to the track by the consuming UI layer.
  }

  /// Hang up / end the call. Closes the peer connection and releases local
  /// and remote streams. Stream controllers are closed by [dispose].
  Future<void> hangUp() async {
    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _created = false;
    await _localStream?.dispose();
    _localStream = null;
    await _remoteStream?.dispose();
    _remoteStream = null;
    _remoteDescription = null;
  }

  /// Get current peer connection ICE state.
  RTCIceConnectionState get peerConnectionState =>
      _peerConnection?.iceConnectionState ??
      RTCIceConnectionState.RTCIceConnectionStateDisconnected;

  /// Get local media stream.
  MediaStream? get localStream => _localStream;

  /// Get remote media stream.
  MediaStream? get remoteStream => _remoteStream;

  /// Dispose of the WebRTC service and all stream controllers.
  void dispose() {
    _peerConnection?.close();
    _peerConnection = null;
    _created = false;
    _localStream?.dispose();
    _remoteStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _remoteDescription = null;
    _onPeerConnectionStateChanged.close();
    _onLocalStream.close();
    _onRemoteStream.close();
    _onError.close();
  }
}

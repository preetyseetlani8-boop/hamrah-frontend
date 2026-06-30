// CallScreen.dart
// WebRTC peer-to-peer audio call via WebSocket signaling.
// Backend: /calls/ws/{ride_id}  (signals offer / answer / ice_candidate / hangup)
// Frontend: flutter_webrtc handles the actual peer connection & mic/speaker.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../config/api_config.dart';
import '../services/UserSession.dart';

class CallScreen extends StatefulWidget {
  final String contactName;
  final String contactPhone;
  final String callerRole;   // 'driver' or 'passenger'
  final String? vehicleInfo;
  final String? rideId;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.contactName,
    required this.contactPhone,
    required this.callerRole,
    this.vehicleInfo,
    this.rideId,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _isMuted    = false;
  bool _isSpeaker  = true;
  bool _callActive = false;
  bool _isLoading  = true;
  String _status   = 'Connecting…';
  int  _seconds    = 0;
  Timer? _timer;
  Timer? _ringTimer;
  bool _accepted   = false;
  Map<String, dynamic>? _pendingOfferData;

  // ── WebRTC ─────────────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream?       _localStream;
  WebSocketChannel?  _ws;
  bool _isOfferer    = false;   // true → we send the offer (first to join)

  // ── State Locks (Fixes duplication & native state crashes) ─────────────────
  bool _isInitializingPC = false;
  bool _offerSent        = false;
  bool _answerSent       = false;

  // ── ICE queue (collected before remote description is set) ─────────────────
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescSet = false;

  // ── Life-cycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    _accepted = !widget.isIncoming;
    super.initState();
    _startCall();
    if (widget.isIncoming) {
      _startRingingFeedback();
    }
  }

  void _startRingingFeedback() {
    _playRingtone();

    HapticFeedback.vibrate();
    _ringTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted && !_accepted) {
        HapticFeedback.vibrate();
      } else {
        _stopRingtone();
      }
    });
  }

  Future<void> _playRingtone() async {
      try {
        // Added () to invoke the plugin instance
        await FlutterRingtonePlayer().playRingtone(
          asAlarm: false,
        );
      } catch (e) {
        debugPrint('Native ringtone failed to play: $e');
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
    }

    void _stopRingtone() {
      _ringTimer?.cancel();
      _ringTimer = null;
      try {
        // Added () to invoke the plugin instance
        FlutterRingtonePlayer().stop();
      } catch (e) {
        debugPrint('Error stopping native ringtone: $e');
      }
    }

  @override
  void dispose() {
    _timer?.cancel();
    _stopRingtone();
    _closeEverything();
    super.dispose();
  }

  // ── Step 1: notify the other party via backend FCM, then connect WS ────────
  Future<void> _startCall() async {
    if (widget.rideId == null || widget.rideId!.isEmpty) {
      setState(() { _status = 'No active ride'; _isLoading = false; });
      return;
    }

    if (!widget.isIncoming) {
      try {
        await http.post(
          ApiConfig.uri('/calls/notify', query: {'ride_id': widget.rideId!}),
          headers: ApiConfig.jsonHeaders(),
        );
      } catch (_) {}
    }

    _connectSignaling();
  }

  // ── Step 2: connect to signaling WebSocket ─────────────────────────────────
  void _connectSignaling() {
    final baseUri = Uri.parse(ApiConfig.baseUrl);
    final wsUri = baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/calls/ws/${widget.rideId}',
      queryParameters: {'token': UserSession.token},
    );

    try {
      _ws = IOWebSocketChannel.connect(
        wsUri,
        headers: const {
          'ngrok-skip-browser-warning': 'true',
          'User-Agent': 'HamrahFlutterApp',
        },
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 10),
      );
    } catch (e) {
      _setStatus('Signaling error: $e');
      return;
    }

    _ws!.stream.listen(
      _onSignalingMessage,
      onError: (e) => _setStatus('Signaling error: $e'),
      onDone: _onSignalingDone,
    );
  }

  // ── Step 3: handle signaling messages ─────────────────────────────────────
  void _onSignalingMessage(dynamic raw) async {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = data['type'] as String?;

    switch (type) {
      case 'waiting_for_peer':
        _setStatus('Waiting for other party…');
        _isOfferer = true;
        await _createPeerConnection();
        break;

      case 'accept':
      case 'peer_ready':
        if (_pc == null && _accepted) {
          _isOfferer = false;
          await _createPeerConnection();
        }
        if (_isOfferer) {
          await _sendOffer();
        }
        break;

      case 'ringing':
        if (_isOfferer) _setStatus('Ringing…');
        break;

      case 'offer':
        if (!_accepted) {
          _pendingOfferData = data;
          _sendSignal({'type': 'ringing'});
          _setStatus('Incoming call…');
        } else {
          await _handleOffer(data);
        }
        break;

      case 'answer':
        await _handleAnswer(data);
        break;

      case 'ice_candidate':
        await _handleIceCandidate(data);
        break;

      case 'hangup':
        _remoteHangup();
        break;

      default:
        break;
    }
  }

  void _onSignalingDone() {
    if (mounted && _callActive) {
      _setStatus('Disconnected');
      _endCall();
    }
  }

  // ── WebRTC helpers ─────────────────────────────────────────────────────────
  Future<void> _createPeerConnection() async {
    if (_pc != null || _isInitializingPC) return;
    _isInitializingPC = true;

    final config = {
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302'
          ]
        }
      ]
    };

    try {
      _pc = await createPeerConnection(config);

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      for (final track in _localStream!.getAudioTracks()) {
        _pc!.addTrack(track, _localStream!);
      }

      try {
        await Helper.setSpeakerphoneOn(_isSpeaker);
      } catch (_) {}

    } catch (e) {
      print("[WebRTC] Hardware allocation exception: $e");
      _setStatus('Microphone error');
      _isInitializingPC = false;
      return;
    }

    _pc!.onIceCandidate = (candidate) {
      _sendSignal({
        'type': 'ice_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _pc!.onIceConnectionState = (state) {
      print("[WebRTC] ICE Connection State: $state");
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _setStatus('Connection lost');
        _endCall();
      }
    };

    _pc!.onConnectionState = (state) {
      print("[WebRTC] Connection State: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          _callActive = true;
          _isLoading  = false;
          _status     = 'Connected';
        });
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && _callActive) setState(() => _seconds++);
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setStatus('Call ended');
        _endCall();
      }
    };

    _isInitializingPC = false;
  }

  Future<void> _sendOffer() async {
    if (_pc == null || _offerSent) return;
    _offerSent = true;

    _setStatus('Calling…');
    try {
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
      await _pc!.setLocalDescription(offer);
      _sendSignal({'type': 'offer', 'sdp': offer.sdp});
    } catch (e) {
      print("[WebRTC] Offer generation failed: $e");
      _offerSent = false;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    if (_pc == null || _answerSent) return;
    _answerSent = true;

    _setStatus('Answering…');
    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(data['sdp'] as String, 'offer'),
      );
      _remoteDescSet = true;
      await _flushPendingCandidates();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _sendSignal({'type': 'answer', 'sdp': answer.sdp});
    } catch (e) {
      print("[WebRTC] Answer handling processing failed: $e");
      _answerSent = false;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(data['sdp'] as String, 'answer'),
      );
      _remoteDescSet = true;
      await _flushPendingCandidates();
    } catch (e) {
      print("[WebRTC] Error configuring remote answer: $e");
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    final candidate = RTCIceCandidate(
      data['candidate'] as String,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    if (_remoteDescSet && _pc != null) {
      await _pc!.addCandidate(candidate);
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> _flushPendingCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  void _sendSignal(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _remoteHangup() {
    _setStatus('Call ended');
    Future.delayed(const Duration(seconds: 1), _endCall);
  }

  // ── Controls ───────────────────────────────────────────────────────────────
  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    for (final t in _localStream?.getAudioTracks() ?? []) {
      t.enabled = !_isMuted;
    }
  }

  void _toggleSpeaker() {
    setState(() => _isSpeaker = !_isSpeaker);
    try {
      Helper.setSpeakerphoneOn(_isSpeaker);
    } catch (_) {}
  }

  void _acceptCall() async {
    _stopRingtone();
    setState(() {
      _accepted = true;
      _status = 'Connecting…';
    });

    if (_pc == null) {
      _isOfferer = false;
      await _createPeerConnection();
    }

    try {
      await http.post(
        ApiConfig.uri('/calls/accept', query: {'ride_id': widget.rideId!}),
        headers: ApiConfig.jsonHeaders(),
      );
    } catch (_) {}

    _sendSignal({'type': 'accept'});
    if (_pendingOfferData != null) {
      await _handleOffer(_pendingOfferData!);
      _pendingOfferData = null;
    } else {
      _sendSignal({'type': 'peer_ready'});
    }
  }

  void _declineCall() {
    _stopRingtone();
    _sendSignal({'type': 'hangup'});
    _closeEverything();
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _endCall() {
    _sendSignal({'type': 'hangup'});
    _timer?.cancel();
    _stopRingtone();
    _closeEverything();
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _closeEverything() {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      _localStream!.dispose();
      _localStream = null;
    }

    if (_pc != null) {
      try {
        _pc!.close();
        _pc!.dispose();
      } catch (_) {}
      _pc = null;
    }

    try {
      _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    _remoteDescSet    = false;
    _isOfferer        = false;
    _isInitializingPC = false;
    _offerSent        = false;
    _answerSent       = false;
    _pendingCandidates.clear();
  }

  void _setStatus(String s) {
    if (mounted) setState(() { _status = s; _isLoading = false; });
  }

  String get _duration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.isIncoming && !_accepted) {
      return _buildIncomingCallUI();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            CircleAvatar(
              radius: 55,
              backgroundColor: Colors.white.withOpacity(0.15),
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 20),

            Text(
              widget.contactName,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              _callActive ? _duration : _status,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.75),
              ),
            ),

            if (widget.vehicleInfo != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.vehicleInfo!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],

            const Spacer(),

            if (_isLoading)
              const CircularProgressIndicator(color: Colors.white)
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlBtn(
                    icon:  _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    onTap: _toggleMute,
                  ),
                  _controlBtn(
                    icon:  _isSpeaker ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                    onTap: _toggleSpeaker,
                    active: _isSpeaker,
                  ),
                ],
              ),
              const SizedBox(height: 40),

              GestureDetector(
                onTap: _endCall,
                child: Container(
                  width: 70, height: 70,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                ),
              ),
            ],

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingCallUI() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green.withOpacity(0.1),
                    ),
                  ),
                  const CircleAvatar(
                    radius: 55,
                    backgroundColor: Color(0xFF00897B),
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Text(
              widget.contactName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Incoming Call…',
              style: TextStyle(
                fontSize: 16,
                color: Colors.greenAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    GestureDetector(
                      onTap: _declineCall,
                      child: Container(
                        width: 70, height: 70,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
                Column(
                  children: [
                    GestureDetector(
                      onTap: _acceptCall,
                      child: Container(
                        width: 70, height: 70,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call, color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Accept', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: active
                ? Colors.white
                : Colors.white.withOpacity(0.15),
            child: Icon(
              icon,
              color: active ? const Color(0xFF1A237E) : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
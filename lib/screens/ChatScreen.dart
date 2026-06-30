import 'dart:async';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/UserSession.dart';

class ChatScreen extends StatefulWidget {
  final String contactName;
  final String contactRole;
  final String? vehicleInfo;
  final String rideRoute;
  final String? rideId;

  const ChatScreen({
    super.key,
    required this.contactName,
    required this.contactRole,
    this.vehicleInfo,
    required this.rideRoute,
    this.rideId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  String get _rideId => widget.rideId ?? UserSession.activeRideId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Auto refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMessages(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_rideId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final msgs = await ChatService.fetchMessages(rideId: _rideId);
      if (!mounted) return;
      setState(() {
        _messages..clear()..addAll(msgs);
        _isLoading = false;
      });
      if (msgs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  static String _nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add({
        'text': text.trim(),
        'fromMe': true,
        'time': _nowTime(),
        'type': 'text',
      });
    });
    _inputController.clear();
    _scrollToBottom();

    if (_rideId.isEmpty) return;

    try {
      await ChatService.sendMessage(rideId: _rideId, text: text.trim());
      await _loadMessages();
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contactName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.rideRoute,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00897B)),
                  )
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final fromMe = msg['fromMe'] == true;
                          return Align(
                            alignment: fromMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: fromMe
                                    ? const Color(0xFF00897B)
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                msg['text'].toString(),
                                style: TextStyle(
                                  color: fromMe ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF00897B),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: () => _send(_inputController.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

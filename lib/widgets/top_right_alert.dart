import 'package:flutter/material.dart';
import 'dart:async';

class TopRightAlert {
  static void show(BuildContext context, {
    required String title,
    required String message,
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _AlertWidget(
        title: title,
        message: message,
        isError: isError,
        actionLabel: actionLabel,
        onAction: () {
          if (onAction != null) onAction();
          overlayEntry?.remove();
          overlayEntry = null;
        },
        onDismiss: () {
          overlayEntry?.remove();
          overlayEntry = null;
        },
      ),
    );

    Overlay.of(context).insert(overlayEntry!);

    // Auto-remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry != null) {
        overlayEntry?.remove();
        overlayEntry = null;
      }
    });
  }
}

class _AlertWidget extends StatefulWidget {
  final String title;
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _AlertWidget({
    Key? key,
    required this.title,
    required this.message,
    required this.isError,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<_AlertWidget> createState() => _AlertWidgetState();
}

class _AlertWidgetState extends State<_AlertWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _offset = Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 Using your Teal theme for Success and Red for Error
    final List<Color> gradientColors = widget.isError
        ? [const Color(0xFFEF5350), const Color(0xFFC62828)] // Red Gradient
        : [const Color(0xFF00BFA5), const Color(0xFF00796B)]; // Teal Gradient

    final IconData icon = widget.isError ? Icons.error_outline : Icons.check_circle_outline;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offset,
          child: FadeTransition(
            opacity: _opacity,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.90,
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.message,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (widget.actionLabel != null && widget.onAction != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    TextButton(
                      onPressed: widget.onAction,
                      child: Text(
                        widget.actionLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.yellowAccent,
                        ),
                      ),
                    )
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
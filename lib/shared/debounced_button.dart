import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';

class DebouncedButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final bool isOutlined;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? width;
  final double height;
  final bool enabled;

  const DebouncedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isOutlined = false,
    this.backgroundColor,
    this.foregroundColor,
    this.width = double.infinity,
    this.height = 48.0,
    this.enabled = true,
  });

  @override
  State<DebouncedButton> createState() => _DebouncedButtonState();
}

class _DebouncedButtonState extends State<DebouncedButton> {
  bool _isProcessing = false;

  Future<void> _handleTap() async {
    if (_isProcessing || widget.onPressed == null || !widget.enabled) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.onPressed!();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canPress = widget.enabled && !_isProcessing && widget.onPressed != null;

    final content = _isProcessing
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : widget.child;

    if (widget.isOutlined) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: OutlinedButton(
          onPressed: canPress ? _handleTap : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.foregroundColor ?? AppTheme.brandNavy,
            side: BorderSide(
              color: canPress ? AppTheme.borderSubtle : const Color(0xFFE2E8F0),
            ),
          ),
          child: content,
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ElevatedButton(
        onPressed: canPress ? _handleTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.backgroundColor ?? AppTheme.brandBlue,
          foregroundColor: widget.foregroundColor ?? Colors.white,
          disabledBackgroundColor: const Color(0xFF93C5FD),
          disabledForegroundColor: Colors.white70,
        ),
        child: content,
      ),
    );
  }
}

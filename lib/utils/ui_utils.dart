import 'package:flutter/material.dart';

class UIUtils {
  /// Shows a premium dialog with a smooth scale and fade transition.
  static Future<T?> showSmoothDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => builder(context),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  /// Shows a premium toast-like message with a smooth slide and fade transition.
  static void showPremiumSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    bool showAtTop = false,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _PremiumToast(
        message: message,
        isError: isError,
        showAtTop: showAtTop,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }
}

class PremiumDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? content;
  final List<Widget>? actions;
  final bool isDestructive;

  const PremiumDialog({
    super.key,
    required this.icon,
    this.iconColor = const Color(0xFF3D7DFE),
    required this.title,
    this.subtitle,
    this.content,
    this.actions,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = isDestructive ? Colors.red.shade700 : iconColor;
    final headerBgColor = isDestructive 
        ? Colors.red.shade50.withOpacity(0.5) 
        : iconColor.withOpacity(0.05);
    final iconCircleColor = isDestructive 
        ? Colors.red.shade100 
        : iconColor.withOpacity(0.1);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: headerBgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: iconCircleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: effectiveIconColor, size: 36),
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                      fontFamily: 'Inter',
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                        fontFamily: 'Inter',
                        height: 1.5,
                      ),
                    ),
                  ],
                  
                  if (content != null) ...[
                     const SizedBox(height: 24),
                     content!,
                  ],
                  
                  if (actions != null) ...[
                    const SizedBox(height: 32),
                    Row(
                      children: actions!.map((a) {
                        final isLast = actions!.last == a;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: isLast ? 0 : 12),
                            child: a,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumToast extends StatefulWidget {
  final String message;
  final bool isError;
  final bool showAtTop;
  final VoidCallback onDismiss;

  const _PremiumToast({
    required this.message,
    required this.isError,
    required this.showAtTop,
    required this.onDismiss,
  });

  @override
  State<_PremiumToast> createState() => _PremiumToastState();
}

class _PremiumToastState extends State<_PremiumToast> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offset;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _offset = Tween<Offset>(
      begin: Offset(0, widget.showAtTop ? -1.75 : 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: widget.showAtTop ? Alignment.topCenter : Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: widget.showAtTop ? 20 : 0,
            bottom: widget.showAtTop ? 0 : 100,
          ),
          child: SlideTransition(
            position: _offset,
            child: FadeTransition(
              opacity: _fade,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: widget.isError ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

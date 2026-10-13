import 'package:material_ui/material_ui.dart';

/// Story's compact follow pill, with a larger transparent hit target.
class FeedFollowButton extends StatefulWidget {
  const FeedFollowButton({
    super.key,
    required this.followed,
    this.attribute,
    this.onPressed,
  });
  final bool followed;
  final int? attribute;
  final Future<void> Function()? onPressed;

  @override
  State<FeedFollowButton> createState() => _FeedFollowButtonState();
}

class _FeedFollowButtonState extends State<FeedFollowButton> {
  bool _busy = false;

  Future<void> _press() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = !widget.followed
        ? '关注'
        : switch (widget.attribute) {
            -10 => '特别关注',
            6 => '互相关注',
            _ => '已关注',
          };
    return Semantics(
      button: true,
      label: _busy ? '关注处理中' : label,
      enabled: !_busy && widget.onPressed != null,
      child: Tooltip(
        message: widget.followed ? '$label · 管理关注' : '关注UP主',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !_busy && widget.onPressed != null ? _press : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, maxWidth: 120),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.followed
                      ? const Color(0x33000000)
                      : const Color(0xFFFB7299),
                  borderRadius: BorderRadius.circular(20),
                  border: widget.followed
                      ? Border.all(color: Colors.white54, width: .5)
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 1.5,
                          ),
                        )
                      else
                        Icon(
                          widget.followed
                              ? Icons.check_rounded
                              : Icons.add_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.2,
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

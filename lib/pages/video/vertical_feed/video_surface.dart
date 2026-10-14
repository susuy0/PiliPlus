import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Mount the opaque native texture underneath the preview while it initializes.
/// Removing the preview must follow a new-media frame, rather than player.open.
class FeedVideoSurface extends StatefulWidget {
  const FeedVideoSurface({
    super.key,
    required this.video,
    required this.preview,
    required this.ready,
    required this.pending,
  });
  final Widget video;
  final Widget preview;
  final bool ready;
  final bool pending;

  @override
  State<FeedVideoSurface> createState() => _FeedVideoSurfaceState();
}

class _FeedVideoSurfaceState extends State<FeedVideoSurface> {
  Timer? _loadingTimer;
  bool _showLoading = false;
  bool _revealed = false;
  int _generation = 0;

  void _update() {
    final generation = ++_generation;
    if (!widget.ready) {
      _revealed = false;
    } else if (!_revealed) {
      // Let the mounted texture compose before exposing it. Never fade or
      // apply an Opacity layer to a platform video texture.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _generation || !widget.ready) return;
        setState(() => _revealed = true);
      });
    }
    if (!widget.pending) {
      _loadingTimer?.cancel();
      _loadingTimer = null;
      _showLoading = false;
    } else {
      _loadingTimer ??= Timer(const Duration(milliseconds: 700), () {
        if (mounted && widget.pending) setState(() => _showLoading = true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(FeedVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ready != widget.ready || oldWidget.pending != widget.pending)
      _update();
  }

  @override
  void dispose() {
    _generation++;
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.video,
      if (!_revealed)
        Positioned.fill(child: IgnorePointer(child: widget.preview)),
      if (_showLoading && widget.pending)
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '加载中...',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
    ],
  );
}

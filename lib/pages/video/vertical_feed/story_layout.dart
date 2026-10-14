import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Story overlays metadata on fitted video; compact layouts reserve its height.
/// All descendants belong to one moving page; navigation lives outside it.
class FeedStoryLayout extends StatelessWidget {
  const FeedStoryLayout({
    super.key,
    required this.video,
    required this.information,
    required this.actions,
    required this.footer,
    this.topInset = 0,
    this.bottomInset = 0,
    this.clean = false,
    this.overlay = false,
  });
  final Widget video, information, actions, footer;
  final double topInset, bottomInset;
  final bool clean, overlay;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final top = math.min(topInset, box.maxHeight * .25);
      final bottom = math.min(bottomInset, box.maxHeight * .12);
      final footerHeight = math.min(64.0, box.maxHeight * .20);
      return Material(
        color: Colors.black,
        child: Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (overlay) ...[
                Positioned.fill(bottom: clean ? 0 : footerHeight, child: video),
                if (!clean) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: footerHeight,
                    height: box.maxHeight * .38,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xA6000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 72,
                    bottom: footerHeight + 6,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: box.maxHeight * .38,
                      ),
                      child: information,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: footerHeight,
                    child: footer,
                  ),
                ],
              ] else
                Column(
                  children: [
                    Expanded(child: SizedBox.expand(child: video)),
                    if (!clean)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: box.maxHeight * .34,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 76, 0),
                          child: information,
                        ),
                      ),
                    if (!clean) SizedBox(height: footerHeight, child: footer),
                  ],
                ),
              if (!clean)
                Positioned(
                  right: 4,
                  bottom: footerHeight + 8,
                  top: 0,
                  width: 64,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomCenter,
                      child: actions,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class FeedContentTags extends StatelessWidget {
  const FeedContentTags({super.key, required this.labels});
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final label in labels)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x55000000),
            border: Border.all(color: Colors.white24, width: .5),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label.contains('充电')) ...[
                Container(
                  width: 15,
                  height: 15,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFB7299),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 13),
                ),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

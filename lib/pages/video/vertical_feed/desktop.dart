import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/text_field/editable_text.dart'
    as pili;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

enum FeedCommand {
  previous,
  next,
  playPause,
  backward,
  forward,
  volumeUp,
  volumeDown,
  mute,
  fullscreen,
  pip,
  comments,
  like,
  favorite,
  more,
  details,
  help,
  back,
}

class FeedDesktopInput extends StatefulWidget {
  const FeedDesktopInput({
    super.key,
    required this.child,
    required this.onCommand,
    this.keyboardEnabled = true,
    this.navigationEnabled = true,
  });
  final Widget child;
  final ValueChanged<FeedCommand> onCommand;
  final bool keyboardEnabled;
  final bool navigationEnabled;
  @override
  State<FeedDesktopInput> createState() => _FeedDesktopInputState();
}

class _FeedDesktopInputState extends State<FeedDesktopInput> {
  final _focus = FocusNode(debugLabel: 'Continuous feed');
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _editing {
    final context = FocusManager.instance.primaryFocus?.context;
    var editing = false;
    context?.visitAncestorElements((element) {
      if (element.widget is EditableText ||
          element.widget is pili.EditableText) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.keyboardEnabled ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_editing) {
      if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
        FocusManager.instance.primaryFocus?.unfocus();
        _focus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final shifted = HardwareKeyboard.instance.isShiftPressed;
    final command = switch (key) {
      LogicalKeyboardKey.arrowUp =>
        shifted ? FeedCommand.volumeUp : FeedCommand.previous,
      LogicalKeyboardKey.arrowDown =>
        shifted ? FeedCommand.volumeDown : FeedCommand.next,
      LogicalKeyboardKey.pageUp => FeedCommand.previous,
      LogicalKeyboardKey.pageDown => FeedCommand.next,
      LogicalKeyboardKey.space => FeedCommand.playPause,
      LogicalKeyboardKey.arrowLeft => FeedCommand.backward,
      LogicalKeyboardKey.arrowRight => FeedCommand.forward,
      LogicalKeyboardKey.keyM => FeedCommand.mute,
      LogicalKeyboardKey.keyF => FeedCommand.fullscreen,
      LogicalKeyboardKey.keyP => FeedCommand.pip,
      LogicalKeyboardKey.keyC => FeedCommand.comments,
      LogicalKeyboardKey.keyL => FeedCommand.like,
      LogicalKeyboardKey.keyE => FeedCommand.favorite,
      LogicalKeyboardKey.keyO => FeedCommand.more,
      LogicalKeyboardKey.keyV => FeedCommand.details,
      LogicalKeyboardKey.keyH => FeedCommand.help,
      LogicalKeyboardKey.escape => FeedCommand.back,
      _ => null,
    };
    if (command == null) return KeyEventResult.ignored;
    final navigation =
        command == FeedCommand.next || command == FeedCommand.previous;
    if (navigation && !widget.navigationEnabled) return KeyEventResult.ignored;
    if (event is KeyDownEvent ||
        (event is KeyRepeatEvent &&
            !navigation &&
            {
              FeedCommand.backward,
              FeedCommand.forward,
              FeedCommand.volumeUp,
              FeedCommand.volumeDown,
            }.contains(command))) {
      widget.onCommand(command);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _key,
    child: widget.child,
  );
}

class FeedWheelGate {
  Timer? _idle;
  double _distance = 0;
  bool _turned = false;
  void add(double delta, ValueChanged<int> turn) {
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 250), () {
      _distance = 0;
      _turned = false;
    });
    if (_turned) return;
    _distance += delta;
    if (_distance.abs() >= 24) {
      _turned = true;
      turn(_distance > 0 ? 1 : -1);
    }
  }

  void dispose() => _idle?.cancel();
}

/// Place inside a PageView item to resolve the wheel before its Scrollable.
class FeedWheelRegion extends StatefulWidget {
  const FeedWheelRegion({
    super.key,
    required this.child,
    required this.onTurn,
    this.enabled = true,
    this.gate,
  });
  final Widget child;
  final ValueChanged<int> onTurn;
  final bool enabled;
  final FeedWheelGate? gate;
  @override
  State<FeedWheelRegion> createState() => _FeedWheelRegionState();
}

class _FeedWheelRegionState extends State<FeedWheelRegion> {
  final _ownedGate = FeedWheelGate();
  @override
  void dispose() {
    _ownedGate.dispose();
    super.dispose();
  }

  void _scroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs())
      return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (widget.enabled)
        (widget.gate ?? _ownedGate).add(event.scrollDelta.dy, widget.onTurn);
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerSignal: _scroll,
    child: widget.child,
  );
}

class FeedDesktopFrame extends StatelessWidget {
  final bool enabled;
  const FeedDesktopFrame({super.key, required this.child, this.enabled = true});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: enabled ? 1100 : double.infinity),
        child: child,
      ),
    ),
  );
}

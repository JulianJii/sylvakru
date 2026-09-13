import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// Playing indicator: three bars bouncing while playing, frozen when paused.
class PlayingBarsIcon extends StatefulWidget {
  const PlayingBarsIcon({
    required this.playing,
    required this.color,
    this.size = 35,
    super.key,
  });

  final bool playing;
  final Color color;
  final double size;

  @override
  State<PlayingBarsIcon> createState() => _PlayingBarsIconState();
}

class _PlayingBarsIconState extends State<PlayingBarsIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  void _sync() {
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = .25;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PlayingBarsIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox.square(
          dimension: widget.size,
          child: Row(
            mainAxisAlignment: .spaceEvenly,
            crossAxisAlignment: .center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: widget.size / 8,
                  height:
                      widget.size *
                      (.35 +
                          .3 *
                              (1 +
                                  sin(
                                    2 * pi * ((_controller.value + i / 3) % 1),
                                  ))),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: .circular(widget.size),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

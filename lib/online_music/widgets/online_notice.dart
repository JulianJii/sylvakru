// 在线音乐页顶部的下滑通知。
//
// 从 online_music_page.dart 抽出来单独成文件。

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/online_music/theme/online_theme.dart';

/// 当前挂在屏上的通知。同一时刻只留一条：新的一条直接把上一条顶掉。
OverlayEntry? _noticeEntry;

/// 屏幕顶部往下滑出一条通知，[duration] 后自动收回（点一下也可以立刻收起）。
///
/// 不用 SnackBar：它是从底部弹的，而且页面里再配一条内嵌提示就会一次冒出来
/// 两条，所以在线音乐页的提示统一走这一条通路。
void showOnlineNotice(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  dismissOnlineNotice();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _NoticeBanner(
      message: message,
      duration: duration,
      onDone: () {
        if (entry.mounted) entry.remove();
        if (identical(_noticeEntry, entry)) _noticeEntry = null;
      },
    ),
  );
  _noticeEntry = entry;
  overlay.insert(entry);
}

/// 收起当前通知；没有就是空操作。
void dismissOnlineNotice() {
  final entry = _noticeEntry;
  _noticeEntry = null;
  if (entry != null && entry.mounted) entry.remove();
}

class _NoticeBanner extends StatefulWidget {
  const _NoticeBanner({
    required this.message,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final Duration duration;

  /// 收起动画播完（或者被点掉）后回调，由调用方把 OverlayEntry 摘掉。
  final VoidCallback onDone;

  @override
  State<_NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<_NoticeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, -1), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 先滑回去再摘 entry，直接摘会"啪"地消失。
  Future<void> _dismiss() async {
    _timer?.cancel();
    if (mounted) await _controller.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _controller,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Material(
                    color: OnlinePalette.surfaceAlt,
                    elevation: 8,
                    shadowColor: Colors.black45,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: OnlinePalette.danger.withAlpha(90)),
                    ),
                    child: InkWell(
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: OnlinePalette.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.message,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: OnlinePalette.text,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              color: OnlinePalette.textFaint,
                              onPressed: _dismiss,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
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

// 在线音乐模块自己的"无边框窗口标题栏"：拖动移动 + 双击最大化 + 窗口按钮。
//
// 桌面端窗口是 TitleBarStyle.hidden + windowButtonVisibility: false，系统标题栏
// 整个没有，移动窗口只能靠 windowManager.startDragging() 手动触发。主界面的
// TitleBar / Sidebar 各带一块拖动区，而在线音乐页和它的播放详情页都是整屏推在
// rootNavigator 上、把主界面标题栏整块盖住的，所以必须自己补一套，否则窗口
// 在这两页里完全拖不动。
//
// 写法与主界面 landscape_view/title_bar.dart 保持一致：拖动层垫在 Stack 底层，
// 内容盖在上层 —— 空白区命中拖动层，按钮自己抢走点击，两者互不干扰。

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/services/my_window_listener.dart';
import 'package:sylvakru/online_music/online_music_page.dart';
import 'package:window_manager/window_manager.dart';

/// 页面顶部的窗口拖动区。
///
/// 拖动 = 移动窗口，双击 = 最大化 / 还原。移动端不参与，直接透传内容。
class WindowDragArea extends StatefulWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  State<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends State<WindowDragArea> {
  /// startDragging() 在 Windows 上是模态的：发出 WM_SYSCOMMAND(SC_MOVE) 后
  /// 进入自己的消息循环，鼠标松开才返回，期间不能重复调用。
  bool _dragging = false;

  Future<void> _startDragging() async {
    if (_dragging) return;
    // 最大化 / 全屏时拖动没有意义，Win10 上还会把窗口拽出屏幕。
    if (isFullScreenNotifier.value || isMaximizedNotifier.value) return;
    _dragging = true;
    try {
      await windowManager.startDragging();
    } finally {
      _dragging = false;
    }
  }

  Future<void> _toggleMaximize() async {
    if (isFullScreenNotifier.value) return;
    if (isMaximizedNotifier.value) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isMobile) return widget.child;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => _startDragging(),
            onDoubleTap: _toggleMaximize,
            // 吃掉点击：无边框窗口点到非交互区域时 Windows 会响系统提示音
            onTap: () {},
          ),
        ),

        // 内容在上层：按钮、输入框照旧命中
        widget.child,
      ],
    );
  }
}

/// 标准窗口控制按钮（最小化 / 最大化 / 关闭），图标与行为跟主界面标题栏一致。
///
/// 全屏和移动端下不显示 —— 与主界面 TitleBar 的处理相同。
class WindowControls extends StatelessWidget {
  const WindowControls({super.key, this.color});

  /// 图标颜色，默认用在线页自己的次级前景色（vivid 主题下全局图标色是黑的，
  /// 压在在线页的深色底上看不见）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (isMobile) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: isFullScreenNotifier,
      builder: (context, isFullScreen, child) {
        if (isFullScreen) return const SizedBox.shrink();

        final foreground = color ?? OnlinePalette.textDim;
        return Row(
          mainAxisSize: .min,
          children: [
            IconButton(
              color: foreground,
              onPressed: () => windowManager.minimize(),
              icon: ImageIcon(minimizeImage),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isMaximizedNotifier,
              builder: (context, isMaximized, child) {
                return IconButton(
                  color: foreground,
                  onPressed: () => isMaximized
                      ? windowManager.unmaximize()
                      : windowManager.maximize(),
                  icon: ImageIcon(
                    isMaximized ? unmaximizeImage : maximizeImage,
                  ),
                );
              },
            ),
            IconButton(
              color: foreground,
              onPressed: () => windowManager.close(),
              icon: ImageIcon(closeImage),
            ),
          ],
        );
      },
    );
  }
}

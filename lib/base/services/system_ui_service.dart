import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sylvakru/base/app.dart';

/// 是否启用重力感应旋屏。关掉后锁在当前方向，不再跟随设备转动。
final autoRotateNotifier = ValueNotifier(true);

/// 按 [autoRotateNotifier] 应用旋屏策略：开启时把方向交回系统（空列表 = 交给
/// 系统默认，即跟随系统自动旋转），关闭时锁在当前方向。桌面端没有重力感应，
/// 跳过。
///
/// 锁定横屏时把两个横向都放进去（Android 对应 userLandscape），因为从显示
/// 尺寸分不出用户是正着拿还是反着拿，只锁一个方向可能把界面转成镜像 180°。
/// 代价是横屏下翻转 180° 仍会跟着转——比倒过来显示好。
Future<void> applyScreenRotation() async {
  if (!isMobile) {
    return;
  }
  final size = PlatformDispatcher.instance.views.first.display.size;
  final landscape = size.width > size.height;

  await SystemChrome.setPreferredOrientations(
    autoRotateNotifier.value
        ? const []
        : landscape
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [DeviceOrientation.portraitUp],
  );
}

SystemUiMode? _appliedUiMode;

// 系统 UI 模式只在目标变化时应用，不能放在 build 里每次重设：全面屏手势
// 上滑时系统临时显示系统栏 → insets 变化触发重建 → 立刻又把栏藏回去，
// 返回桌面的手势被打断（平板宽屏沉浸模式下上滑卡住回不了桌面）。
void applySystemUiMode({SystemUiMode? mode, bool forceApply = false}) {
  if (!forceApply) {
    if (_appliedUiMode == mode) {
      return;
    }
    _appliedUiMode = mode;
  }

  if (_appliedUiMode == SystemUiMode.manual) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  } else {
    if (_appliedUiMode != null) {
      SystemChrome.setEnabledSystemUIMode(_appliedUiMode!);
    }
  }
}

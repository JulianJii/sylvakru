part of '../../layer/settings_layer.dart';

void _leaveSettings() {
  if (layersManager.settingsPagePushed) {
    layersManager.closeSettings();
    return;
  }
  // 兜底：宽布局把设置当作 root layer 切了进来，没有路由可 pop，
  // 回到歌曲页（和 removeLayerIfNeed 里的兜底保持一致）
  layersManager.switchRootLayer('songs');
}

/// 竖屏下的设置页：作为一条可返回的路由被 push 出来，而不是切换 root layer。
/// 返回箭头 / 系统返回键 / iOS 侧滑都会回到进入设置前的那一层。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: mainPageThemeNotifier,
      builder: (context, value, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: _leaveSettings,
            ),
            backgroundColor: Colors.transparent,
            systemOverlayStyle: mainPageThemeNotifier.value == .dark
                ? .light
                : .dark,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(AppLocalizations.of(context).settings),
            centerTitle: true,
          ),
          body: SettingsList(iconSize: 30),
        );
      },
    );
  }
}

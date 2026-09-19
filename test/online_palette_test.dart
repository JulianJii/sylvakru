// 在线音乐配色跟随全局主题：浅/深色取主题页面色，vivid 取封面主色压暗。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/online_music/online_music_page.dart';

void main() {
  test('在线音乐配色跟随全局主题', () {
    for (final theme in ThemeType.values) {
      mainPageThemeNotifier.value = theme;
      colorManager.updateMainPageColors();

      // 全屏页必须有自带的不透明底色，否则会透到透明窗口外的桌面上。
      expect(OnlinePalette.bg.a, 1.0, reason: '$theme');

      // 压在强调色上的前景色要和强调色反着来。
      expect(
        OnlinePalette.onPrimary == Colors.black,
        OnlinePalette.primary.computeLuminance() > 0.5,
        reason: '$theme',
      );

      // 三档文字逐级变淡。
      expect(OnlinePalette.textFaint.a, lessThan(OnlinePalette.textDim.a));
      expect(OnlinePalette.textDim.a, lessThanOrEqualTo(OnlinePalette.text.a));
    }

    mainPageThemeNotifier.value = ThemeType.light;
    colorManager.updateMainPageColors();
    expect(OnlinePalette.bg, pageBackgroundColor.lightModeValue);
    expect(OnlinePalette.surface, panelColor.lightModeValue);
    expect(OnlinePalette.surfaceAlt, searchFieldColor.lightModeValue);
    expect(OnlinePalette.text, textColor.lightModeValue);

    mainPageThemeNotifier.value = ThemeType.dark;
    colorManager.updateMainPageColors();
    expect(OnlinePalette.bg, pageBackgroundColor.darkModeValue);
    expect(OnlinePalette.text, textColor.darkModeValue);
  });
}

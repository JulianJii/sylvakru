// 在线音乐页的配色与 ThemeData。
//
// 从 online_music_page.dart 抽出来单独成文件：配色被页面、播放详情页、
// 下载面板、窗口拖动区多处引用，放在页面文件里会让它们反向依赖页面。

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/color_manager.dart';

/// 在线音乐页的配色。
///
/// 全部映射到本地音乐那套全局主题（[ColorManager]），所以页面跟随
/// vivid / 浅色 / 深色三种主题，而不是自带一套固定的紫色深色皮肤。
class OnlinePalette {
  const OnlinePalette._();

  /// 语义色（失败 / 成功 / 警告）跟主题无关，保持固定。
  static const Color danger = Color(0xFFF87171);
  static const Color success = Color(0xFF34D399);
  static const Color warn = Color(0xFFFBBF24);

  static bool get _vivid => mainPageThemeNotifier.value == .vivid;

  /// 全屏页要自带不透明底色：vivid 用当前封面主色压暗（本地音乐那层半透明
  /// 页面色是叠在封面背景上的，这个页面没有那层背景），浅/深色直接用页面色。
  static Color get bg => _vivid
      ? Color.alphaBlend(currentCoverArtColor.withAlpha(160), Colors.black)
      : pageBackgroundColor.value;

  /// 卡片 / 面板底色。深色主题下 `panelColor` 和页面色是同一个值，靠边框区分。
  static Color get surface => _vivid
      ? Color.alphaBlend(Colors.white.withAlpha(24), bg)
      : panelColor.value;

  /// 输入框、次级按钮、分隔线。
  static Color get surfaceAlt => _vivid
      ? Color.alphaBlend(Colors.white.withAlpha(48), bg)
      : searchFieldColor.value;

  /// 强调色：vivid 用封面算出来的对比色（和歌词页同一套），浅/深色用主题高亮色。
  static Color get primary =>
      _vivid ? contrastColorTheme.accent : highlightTextColor.value;
  static Color get primaryLight => primary;

  /// 压在强调色上的前景色，按强调色自身明度取黑或白。
  static Color get onPrimary =>
      primary.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  static Color get text =>
      _vivid ? contrastColorTheme.regular : textColor.value;
  static Color get textDim => text.withAlpha(190);
  static Color get textFaint => text.withAlpha(140);
}

ThemeData buildOnlineTheme() {
  final isLight = mainPageThemeNotifier.value == .light;
  final base = ThemeData(
    brightness: isLight ? Brightness.light : Brightness.dark,
    useMaterial3: true,
  );
  return base.copyWith(
    scaffoldBackgroundColor: OnlinePalette.bg,
    colorScheme:
        (isLight ? const ColorScheme.light() : const ColorScheme.dark())
            .copyWith(
              primary: OnlinePalette.primary,
              onPrimary: OnlinePalette.onPrimary,
              secondary: OnlinePalette.primaryLight,
              surface: OnlinePalette.surface,
              onSurface: OnlinePalette.text,
              error: OnlinePalette.danger,
            ),
    textTheme: base.textTheme
        .apply(bodyColor: OnlinePalette.text, displayColor: OnlinePalette.text)
        .apply(fontFamily: fontFamilyNotifier.value),
    iconTheme: IconThemeData(color: OnlinePalette.textDim),
    dividerColor: OnlinePalette.surfaceAlt,
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      activeTrackColor: OnlinePalette.primary,
      inactiveTrackColor: OnlinePalette.text.withAlpha(60),
      thumbColor: OnlinePalette.primaryLight,
      overlayColor: OnlinePalette.primary.withAlpha(40),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: OnlinePalette.surfaceAlt,
      contentTextStyle: TextStyle(color: OnlinePalette.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OnlinePalette.surfaceAlt,
      hintStyle: TextStyle(color: OnlinePalette.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

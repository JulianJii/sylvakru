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

  /// 列表行 / 卡片底色与描边。行要压在页面渐变上还能看出边界，所以比
  /// [surface] 再淡一档，边框统一由前景色派生，浅色深色都不刺眼。
  static Color get card => _vivid
      ? Color.alphaBlend(Colors.white.withAlpha(14), bg)
      : surface;
  static Color get cardBorder => _vivid
      ? Colors.white.withAlpha(26)
      : text.withAlpha(20);

  /// 鼠标悬停叠加色（画在行自己身上，见 TrackRow 的 hover 处理）。
  static Color get hover => _vivid
      ? Colors.white.withAlpha(18)
      : text.withAlpha(14);

  /// 当前播放中的行：低透明主色底 + 主色描边。
  static Color get selected => primary.withAlpha(26);
  static Color get selectedBorder => primary.withAlpha(90);

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

/// 布局度量：页面、列表、对话框共用一套数值，避免各处手写魔数。
///
/// 全部按「实际宽度」分档，不再用 `width > height` 判断横竖屏 —— 桌面窗口
/// 是宽而矮的，移动端横屏也只是矮，两者需要的并不是同一套布局。
class OnlineLayout {
  const OnlineLayout._();

  /// 内容区最大宽度：超宽窗口居中，列表行不会一路拉到大半屏。
  static const double maxContentWidth = 1240;

  /// 页面左右留白。
  static const double gutterNarrow = 16;
  static const double gutterWide = 24;

  /// 结果行高（TrackRow / PlaylistRow）。
  static const double trackRowHeight = 68;
  static const double playlistRowHeight = 76;

  /// 网格单列上限宽度，列数由 `SliverGridDelegateWithMaxCrossAxisExtent` 推导。
  static const double gridMaxExtent = 460;

  /// 圆角：标签 / 行与输入 / 卡片封面 / 对话框。
  static const double radiusTag = 6;
  static const double radiusRow = 10;
  static const double radiusCard = 12;
  static const double radiusDialog = 16;

  /// 宽度断点。
  static const double compactBreakpoint = 640;
  static const double wideBreakpoint = 1000;

  static bool isCompact(double width) => width < compactBreakpoint;
  static bool isWide(double width) => width >= wideBreakpoint;

  static double gutter(double width) =>
      isCompact(width) ? gutterNarrow : gutterWide;
}

/// 统一字号：同一层级的信息在各处保持一致，而不是 12/13/14 混用。
class OnlineText {
  const OnlineText._();

  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle title = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle body = TextStyle(fontSize: 13);
  static const TextStyle caption = TextStyle(fontSize: 12);

  /// 标签：比 caption 再小一档。
  static const TextStyle tag = TextStyle(fontSize: 11);

  /// 时长、进度时间这类数字要竖着对齐，用等宽数字。
  static const TextStyle numeric = TextStyle(
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
  );
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
              secondaryContainer: OnlinePalette.primary.withAlpha(24),
              surface: OnlinePalette.surface,
              onSurface: OnlinePalette.text,
              outline: OnlinePalette.cardBorder,
              error: OnlinePalette.danger,
            ),
    textTheme: base.textTheme
        .apply(bodyColor: OnlinePalette.text, displayColor: OnlinePalette.text)
        .apply(fontFamily: fontFamilyNotifier.value),
    iconTheme: IconThemeData(color: OnlinePalette.textDim),
    dividerColor: OnlinePalette.cardBorder,
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      activeTrackColor: OnlinePalette.primary,
      inactiveTrackColor: OnlinePalette.text.withAlpha(60),
      thumbColor: OnlinePalette.primaryLight,
      overlayColor: OnlinePalette.primary.withAlpha(40),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      crossAxisMargin: 2,
      thumbColor: WidgetStatePropertyAll(OnlinePalette.text.withAlpha(60)),
      thumbVisibility: const WidgetStatePropertyAll(false),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: OnlinePalette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(fontSize: 12, color: OnlinePalette.text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: OnlinePalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OnlineLayout.radiusDialog),
      ),
      titleTextStyle: OnlineText.dialogTitle.copyWith(
        color: OnlinePalette.text,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: OnlinePalette.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OnlineLayout.radiusCard),
      ),
      textStyle: TextStyle(fontSize: 13, color: OnlinePalette.text),
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
        borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

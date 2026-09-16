import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/base/widgets/buttons.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/landscape_view/speaker.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/landscape_view/volume_bar.dart';
import 'package:sylvakru/layer/lyrics_page_layer.dart';
import 'package:sylvakru/base/widgets/lyric_list_view.dart';
import 'package:sylvakru/base/widgets/seekbar.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/utils/dynamic_lyrics_page_route.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:text_scroll/text_scroll.dart';

class LandscapeLyricsPage extends StatefulWidget {
  const LandscapeLyricsPage({super.key});

  @override
  State<StatefulWidget> createState() => _LandscapeLyricsPageState();
}

class _LandscapeLyricsPageState extends State<LandscapeLyricsPage> {
  Timer? immersiveModeTimer;
  final ValueNotifier<bool> immersiveModeNotifier = ValueNotifier(false);

  final dragOffsetNotifier = ValueNotifier(0.0);

  final draggingNotifier = ValueNotifier(false);

  int _animationDuration = 0;

  Timer? concealRouteTimer;

  @override
  void dispose() {
    immersiveModeTimer?.cancel();
    concealRouteTimer?.cancel();
    immersiveModeNotifier.dispose();
    dragOffsetNotifier.dispose();
    draggingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    immersiveModeTimer?.cancel();
    immersiveModeTimer = Timer(const Duration(milliseconds: 5000), () {
      immersiveModeNotifier.value = true;
    });
    final mediaQueryData = MediaQuery.of(context);
    final pageWidth = mediaQueryData.size.width;
    final pageHight =
        mediaQueryData.size.height -
        mediaQueryData.padding.top -
        mediaQueryData.padding.bottom;
    return ValueListenableBuilder(
      valueListenable: immersiveModeNotifier,
      builder: (context, value, child) {
        return MouseRegion(
          cursor: value ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (event) {
            immersiveModeNotifier.value = false;
            immersiveModeTimer?.cancel();
            immersiveModeTimer = Timer(const Duration(milliseconds: 5000), () {
              immersiveModeNotifier.value = true;
            });
          },
          child: child,
        );
      },
      child: GestureDetector(
        // 移动端横屏靠下滑关闭歌词页；桌面端不需要，手势回调整体置 null。
        onVerticalDragStart: isMobile ? _dragStart : null,
        onVerticalDragUpdate: isMobile
            ? (details) => _dragUpdate(details.delta.dy, pageHight)
            : null,
        onVerticalDragEnd: isMobile
            ? (details) => _dragEnd(details.primaryVelocity ?? 0, pageHight)
            : null,
        onVerticalDragCancel: isMobile ? _resetDragOffset : null,
        child: ValueListenableBuilder(
          valueListenable: dragOffsetNotifier,
          builder: (context, value, child) {
            return AnimatedContainer(
              duration: Duration(milliseconds: _animationDuration),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, value, 0),
              child: child,
            );
          },
          child: immersiveWideLayoutNotifier.value
              ? content(pageWidth, pageHight)
              : SafeArea(child: content(pageWidth, pageHight)),
        ),
      ),
    );
  }

  /// 关闭歌词页，与桌面端标题栏里的关闭按钮保持同一套收尾逻辑。
  void _closeLyricsPage() {
    displayLyricsPage = false;
    Navigator.pop(context);
  }

  /// 移动端横屏的关闭按钮。这里不能像桌面端标题栏那样跟进沉浸模式：
  /// 移动端没有 hover 事件，immersiveModeNotifier 置 true 后不会再恢复，
  /// 按钮一旦被隐藏就再也点不到，所以必须常驻。
  Widget _mobileCloseButton() {
    return ValueListenableBuilder(
      valueListenable: lyricsPageForegroundColor.valueNotifier,
      builder: (context, value, child) {
        return IconButton(
          color: value,
          onPressed: _closeLyricsPage,
          icon: ImageIcon(fullscreenExitImage),
        );
      },
    );
  }

  void _dragStart(DragStartDetails _) {
    draggingNotifier.value = true;
    concealRouteTimer?.cancel();
    final route = ModalRoute.of(context);
    if (route is DynamicLyricsPageRoute) {
      route.revealRoutesBelow();
    }
  }

  void _dragUpdate(double delta, double pageHight) {
    _animationDuration = 0;
    dragOffsetNotifier.value = (dragOffsetNotifier.value + delta).clamp(
      0.0,
      pageHight,
    );
  }

  void _dragEnd(double velocity, double pageHight) {
    if (dragOffsetNotifier.value * 3 > pageHight || velocity > 500) {
      _closeLyricsPage();
      return;
    }
    _resetDragOffset();
  }

  /// 未达阈值则回弹复位；动画结束后再恢复下层路由的不透明，
  /// 否则回弹过程中下层会一闪而过。
  void _resetDragOffset() {
    _animationDuration = 250;
    dragOffsetNotifier.value = 0.0;
    concealRouteTimer?.cancel();
    concealRouteTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      draggingNotifier.value = false;
      final route = ModalRoute.of(context);
      if (route is DynamicLyricsPageRoute) {
        route.concealRoutesBelow();
      }
    });
  }

  Widget content(double pageWidth, double pageHight) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (context, currentSong, child) {
        // 横向播放页左侧：封面 + 标题信息 + 播放控件需整体放进可用高度，
        // 否则在较矮的窗口/屏幕上左侧 Column 会底部溢出。这里按下方实际占用
        // 高度给封面留余量，把封面上限从「可用高度」里扣掉 chrome 后再取最小。
        double coverArtSize = min(
          pageWidth * (isMobile ? 0.35 : 0.3),
          pageHight * (isMobile ? 0.7 : 0.6),
        );
        if (pageHight >= 600) {
          final infoHeight = pageHight * 0.02 + 64; // 标题 + 歌手/专辑两行 + 上下间距
          final controlsHeight =
              20 + // 进度条
              (35 + 16) + // 播放/暂停按钮(含默认内边距)
              (isMobile ? 0 : 10) + // 音量条(桌面端)
              pageHight * 0.02; // 控件底部间距
          final reserved =
              75 + infoHeight + controlsHeight + 16; // 75=顶部标题栏占位, 16=安全余量
          coverArtSize = min(coverArtSize, max(0, pageHight - reserved));
        }

        return ValueListenableBuilder(
          valueListenable: draggingNotifier,
          builder: (context, value, child) {
            // 拖动关闭时给页面加圆角，与竖屏播放页保持同一手感。
            return Material(
              color: Colors.transparent,
              shape: SmoothRectangleBorder(
                smoothness: 1,
                borderRadius: .circular(value ? dragCornerRadius : 0),
              ),
              clipBehavior: value ? .antiAliasWithSaveLayer : .antiAlias,
              child: child,
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (lyricsPageThemeNotifier.value == .vivid) ...[
                CoverArtWidget(
                  picture: currentSong?.picture,
                  color: colorManager.getSpecificLyricsPageCoverArtBaseColor(),
                ),
                RepaintBoundary(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: pageWidth * 0.03,
                      sigmaY: pageHight * 0.03,
                    ),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      color: currentCoverArtColor.withAlpha(180),
                    ),
                  ),
                ),
              ],

              ValueListenableBuilder(
                valueListenable: lyricsPageBackgroundColor.valueNotifier,
                builder: (context, value, child) {
                  return Container(color: value, child: child);
                },
                child: Row(
                  children: [
                    Spacer(),
                    Column(
                      children: [
                        if (pageHight >= 600) SizedBox(height: 75),
                        Spacer(),
                        Hero(
                          tag: 'cover',
                          flightShuttleBuilder:
                              (
                                flightContext,
                                animation,
                                flightDirection,
                                fromHeroContext,
                                toHeroContext,
                              ) => FittedBox(child: toHeroContext.widget),
                          child: CoverArtWidget(
                            size: coverArtSize,
                            borderRadius: coverArtSize * 0.05,
                            picture: currentSong?.picture,
                            elevation: 15,
                            color: colorManager
                                .getSpecificLyricsPageCoverArtBaseColor(),
                          ),
                        ),
                        if (pageHight >= 600) ...[
                          information(coverArtSize, pageHight, currentSong),
                          playControls(coverArtSize, pageHight, currentSong),
                        ],

                        Spacer(),
                      ],
                    ),
                    SizedBox(width: pageWidth * 0.05),
                    SizedBox(
                      width: pageWidth * 0.45,
                      child: Column(
                        children: [
                          if (!isMobile) SizedBox(height: 75),

                          if (pageHight < 600) ...[
                            SizedBox(height: 15),

                            information(
                              pageWidth * 0.4,
                              pageHight,
                              currentSong,
                            ),
                          ],

                          Expanded(
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(scrollbars: false),
                              child: currentSong == null
                                  ? SizedBox()
                                  : LyricsListView(
                                      key: ValueKey(currentSong),
                                      expanded: pageHight < 600 ? false : true,
                                      lines: currentSong.parsedLyrics!.lines,
                                      isKaraoke:
                                          currentSong.parsedLyrics!.isKaraoke,
                                    ),
                            ),
                          ),

                          if (pageHight < 600) ...[
                            playControls(
                              pageWidth * 0.45,
                              pageHight,
                              currentSong,
                            ),
                            SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: pageWidth * 0.05),
                  ],
                ),
              ),

              Positioned(
                right: pageHight < 600 ? pageWidth * 0.05 : 60,
                bottom: 100,
                child: ValueListenableBuilder(
                  valueListenable: immersiveModeNotifier,
                  builder: (context, value, child) {
                    List<Widget> children = [
                      IconButton(
                        color: lyricsPageForegroundColor.value,
                        onPressed: () {
                          lyricsFontSizeOffsetNotifier.value += 2;
                          setting.save();
                        },
                        icon: Icon(Icons.text_increase_rounded, size: 20),
                      ),
                      IconButton(
                        color: lyricsPageForegroundColor.value,
                        onPressed: () {
                          if (lyricsFontSizeOffsetNotifier.value < -2) {
                            return;
                          }
                          lyricsFontSizeOffsetNotifier.value -= 2;
                          setting.save();
                        },
                        icon: Icon(Icons.text_decrease_rounded, size: 18),
                      ),
                    ];
                    return Offstage(
                      offstage: value,
                      child: pageHight <= 600
                          ? Column(children: children)
                          : Row(children: children),
                    );
                  },
                ),
              ),

              if (!isMobile)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: immersiveModeNotifier,
                    builder: (context, value, child) {
                      return Offstage(offstage: value, child: child);
                    },
                    child: TitleBar(isMainPage: false),
                  ),
                ),

              if (isMobile)
                Positioned(
                  // 这里的 context 位于 SafeArea 内部（padding 已被移除，不会重复计算）；
                  // 沉浸模式下没有 SafeArea，则用刘海/状态栏的 padding 让开。
                  left: MediaQuery.paddingOf(context).left + 20,
                  top: MediaQuery.paddingOf(context).top + 20,
                  child: _mobileCloseButton(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget information(
    double width,
    double pageHight,
    MyAudioMetadata? currentSong,
  ) {
    return Column(
      children: [
        SizedBox(height: pageHight * 0.01),
        SizedBox(
          width: width - 30,
          height: 36,
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: lyricsPageHighlightTextColor.valueNotifier,
              builder: (context, value, child) {
                return TextScroll(
                  key: UniqueKey(),
                  getTitle(currentSong),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: value,
                  ),
                  velocity: const .new(pixelsPerSecond: .new(40, 0)),
                  intervalSpaces: 10,
                  pauseBetween: Duration(seconds: 2),
                );
              },
            ),
          ),
        ),

        SizedBox(
          width: width - 30,
          height: 28,
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: lyricsPageForegroundColor.valueNotifier,
              builder: (context, value, child) {
                return TextScroll(
                  key: UniqueKey(),
                  '${getArtist(currentSong)} - ${getAlbum(currentSong)}',
                  style: TextStyle(fontSize: 14, color: value),
                  velocity: const .new(pixelsPerSecond: .new(40, 0)),
                  intervalSpaces: 10,
                  pauseBetween: Duration(seconds: 2),
                );
              },
            ),
          ),
        ),

        SizedBox(height: pageHight * 0.01),
      ],
    );
  }

  Widget playControls(
    double width,
    double pageHight,
    MyAudioMetadata? currentSong,
  ) {
    return ValueListenableBuilder(
      valueListenable: lyricsPageForegroundColor.valueNotifier,
      builder: (context, value, child) {
        return Column(
          children: [
            SizedBox(
              width: width - 15,
              child: SeekBar(color: value, widgetHeight: 20, seekBarHeight: 10),
            ),

            SizedBox(
              width: width,
              child: Row(
                children: [
                  playModeButton(25, iconColor: value),
                  Spacer(),

                  if (isTV) rewindButton(25, iconColor: value),

                  skip2PreviousButton(25, iconColor: value),

                  playOrPauseButton(35, iconColor: value),

                  skip2NextButton(25, iconColor: value),

                  if (isTV) forwardButton(25, iconColor: value),

                  Spacer(),
                  showPlayQueueButton(25, iconColor: value),
                ],
              ),
            ),
            if (!isMobile)
              SizedBox(
                width: width,
                child: Row(
                  children: [
                    Spacer(),

                    SizedBox(width: 40, child: Speaker(color: value)),
                    SizedBox(
                      height: 10,
                      width: width * 0.5,
                      child: VolumeBar(activeColor: value),
                    ),
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        onPressed: () async {
                          showCenterMessage('Desktop lyrics has been removed');
                        },
                        icon: const ImageIcon(desktopLyricsImage, size: 25),

                        color: value,
                      ),
                    ),
                    Spacer(),
                  ],
                ),
              ),
            SizedBox(height: pageHight * 0.02),
          ],
        );
      },
    );
  }
}

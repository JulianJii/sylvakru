// 在线音乐的播放详情页：从底部播放条向上滑出的封面 + 歌词 + 可拖动的进度条。
//
// 页面自己不持有播放状态：切歌、拖进度都直接作用在 `audioHandler` 上，
// 当前曲目由 [onlineNowPlaying] 提供（`online_music_page` 播放成功时写入），
// 所以关掉页面播放照常继续，重新打开也不会丢封面和歌词。

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/online_music_page.dart';
import 'package:sylvakru/online_music/online_window_drag_area.dart';

/// 当前在播的在线曲目。搜索/歌单结果是唯一来源（封面、歌词都靠它）。
final ValueNotifier<OnlineTrack?> onlineNowPlaying = ValueNotifier(null);

/// 向上滑出播放详情页。`onPrevious` / `onNext` 传 null 表示当前列表里没有
/// 上一首/下一首（跟播放条上按钮的可用状态保持一致）。
Future<void> openOnlinePlayerDetail(
  BuildContext context, {
  VoidCallback? onPrevious,
  VoidCallback? onNext,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => Theme(
        data: buildOnlineTheme(),
        child: OnlinePlayerDetailPage(onPrevious: onPrevious, onNext: onNext),
      ),
      transitionsBuilder: (_, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              ),
          child: child,
        );
      },
    ),
  );
}

class OnlinePlayerDetailPage extends StatefulWidget {
  const OnlinePlayerDetailPage({super.key, this.onPrevious, this.onNext});

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<OnlinePlayerDetailPage> createState() => _OnlinePlayerDetailPageState();
}

class _OnlinePlayerDetailPageState extends State<OnlinePlayerDetailPage> {
  OnlineTrack? _track;
  ParsedLyrics? _lyrics;
  bool _loadingLyrics = false;

  /// 歌词请求代次：切歌后到达的旧响应直接丢掉。
  int _lyricGeneration = 0;

  @override
  void initState() {
    super.initState();
    onlineNowPlaying.addListener(_onTrackChanged);
    currentSongNotifier.addListener(_onTrackChanged);
    _onTrackChanged();
  }

  @override
  void dispose() {
    onlineNowPlaying.removeListener(_onTrackChanged);
    currentSongNotifier.removeListener(_onTrackChanged);
    super.dispose();
  }

  void _onTrackChanged() {
    final playing = onlineNowPlaying.value;
    // 离开在线页后又播了本地音乐的话，残留的 onlineNowPlaying 不再算数。
    final track = playing?.id == currentSongNotifier.value?.id ? playing : null;
    if (track?.id == _track?.id) return;
    _track = track;
    _lyrics = null;
    _loadingLyrics = track != null;
    if (mounted) setState(() {});
    if (track != null) unawaited(_loadLyrics(track));
  }

  Future<void> _loadLyrics(OnlineTrack track) async {
    final generation = ++_lyricGeneration;
    final raw = await onlineApiClient.fetchLyric(track);
    if (!mounted || generation != _lyricGeneration) return;
    final lyrics = ParsedLyrics();
    // 解析复用本地播放页那一套：翻译行、逐字时间、无歌词占位都在这。
    applyLrcParsing(
      lyrics,
      raw.split('\n'),
      noLyricsMessage: '暂无歌词',
      parseFailedMessage: '歌词解析失败',
      songDuration: getDuration(currentSongNotifier.value),
    );
    setState(() {
      _lyrics = lyrics;
      _loadingLyrics = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnlinePalette.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [OnlinePalette.surface, OnlinePalette.bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 顶部

  Widget _buildHeader() {
    // 与在线音乐主页同理：整屏页面盖住了主界面标题栏，顶栏要自带拖动区
    // 和窗口按钮，否则这里拖不动窗口。
    return WindowDragArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: '收起',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ListenableBuilder(
                listenable: currentSongNotifier,
                builder: (context, _) {
                  final song = currentSongNotifier.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _track == null ? '在线音乐' : getTitle(song),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _track == null ? '还没有在播放' : getArtist(song),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            WindowControls(color: OnlinePalette.textDim),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 主体

  Widget _buildBody() {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > size.height;
    final cover = _buildCover();
    final lyrics = _buildLyrics();

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 8),
        child: Row(
          children: [
            Expanded(child: cover),
            const SizedBox(width: 40),
            Expanded(child: lyrics),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: Column(
        children: [
          Flexible(flex: 5, child: cover),
          const SizedBox(height: 18),
          Flexible(flex: 6, child: lyrics),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final track = _track;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (track != null)
          // 封面铺满做背景，模糊 + 压暗，撑住整页的色调。
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Opacity(
                opacity: 0.35,
                child: OnlineCover(
                  track: track,
                  placeholder: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: track == null
                    ? _coverPlaceholder()
                    : OnlineCover(
                        track: track,
                        placeholder: _coverPlaceholder(),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [OnlinePalette.surfaceAlt, OnlinePalette.bg],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: 64,
        color: OnlinePalette.textFaint,
      ),
    );
  }

  Widget _buildLyrics() {
    final lyrics = _lyrics;
    if (lyrics == null) {
      return Center(
        child: _loadingLyrics
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: OnlinePalette.primaryLight,
                ),
              )
            : Text(
                '正在播放本地音乐',
                style: TextStyle(color: OnlinePalette.textFaint),
              ),
      );
    }
    return _LyricsView(key: ValueKey(_track?.id), lyrics: lyrics);
  }

  // ------------------------------------------------------------------ 底部

  Widget _buildControls() {
    final song = currentSongNotifier.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Column(
        children: [
          const OnlineSeekBar(),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一首',
                iconSize: 34,
                onPressed: widget.onPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 26),
              ValueListenableBuilder<bool>(
                valueListenable: isPlayingNotifier,
                builder: (context, isPlaying, _) {
                  return IconButton.filled(
                    tooltip: isPlaying ? '暂停' : '播放',
                    iconSize: 38,
                    padding: const EdgeInsets.all(14),
                    style: IconButton.styleFrom(
                      backgroundColor: OnlinePalette.primary,
                      foregroundColor: OnlinePalette.onPrimary,
                    ),
                    onPressed: song == null ? null : audioHandler.togglePlay,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  );
                },
              ),
              const SizedBox(width: 26),
              IconButton(
                tooltip: '下一首',
                iconSize: 34,
                onPressed: widget.onNext,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 进度条。播放条和详情页共用，所以放在这里。
class OnlineSeekBar extends StatefulWidget {
  const OnlineSeekBar({super.key});

  @override
  State<OnlineSeekBar> createState() => _OnlineSeekBarState();
}

class _OnlineSeekBarState extends State<OnlineSeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioHandler.getPositionStream(),
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration>(
          stream: audioHandler.getDurationStream(),
          initialData: audioHandler.getCurrentDuration(),
          builder: (context, durationSnapshot) {
            var duration = durationSnapshot.data ?? Duration.zero;
            if (duration <= Duration.zero) {
              duration = getDuration(currentSongNotifier.value);
            }
            final max = duration.inMilliseconds.toDouble();
            final position = audioHandler.getPosition();
            final value = (_dragValue ?? position.inMilliseconds.toDouble())
                .clamp(0.0, max <= 0 ? 1.0 : max);

            return Row(
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: value.round())),
                  style: TextStyle(
                    fontSize: 11,
                    color: OnlinePalette.textFaint,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: value,
                    max: max <= 0 ? 1 : max,
                    onChanged: max <= 0
                        ? null
                        : (v) => setState(() => _dragValue = v),
                    onChangeEnd: max <= 0
                        ? null
                        : (v) {
                            setState(() => _dragValue = null);
                            audioHandler.seek(
                              Duration(milliseconds: v.round()),
                            );
                          },
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    fontSize: 11,
                    color: OnlinePalette.textFaint,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 详情页的歌词：跟随播放位置滚动，点一行跳过去。
///
/// ponytail: 没复用 `base/widgets/lyric_list_view.dart` —— 那个读的是本地
/// 播放页的全局配色和迷你模式状态，套在在线这套深色主题上颜色会错；逐字
/// 歌词（karaoke）也没做，在线接口基本只给到行级。
class _LyricsView extends StatefulWidget {
  const _LyricsView({required this.lyrics, super.key});

  final ParsedLyrics lyrics;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ValueNotifier<int> _currentIndex = ValueNotifier(-1);
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _positionSub = audioHandler.getPositionStream().listen(_sync);
    // 首帧滚到当前行时要等列表挂上去。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync(audioHandler.getPosition(), jump: true);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _currentIndex.dispose();
    super.dispose();
  }

  void _sync(Duration position, {bool jump = false}) {
    final lines = widget.lyrics.lines;
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (position < lines[i].start) break;
      index = i;
    }
    if (index == _currentIndex.value) return;
    _currentIndex.value = index;
    if (index < 0 || !_scrollController.isAttached) return;
    if (jump) {
      _scrollController.jumpTo(index: index + 1, alignment: 0.4);
    } else {
      _scrollController.scrollTo(
        index: index + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        alignment: 0.4,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0, 0.12, 0.85, 1],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ScrollablePositionedList.builder(
            itemCount: lines.length + 2,
            itemScrollController: _scrollController,
            physics: const ClampingScrollPhysics(),
            itemBuilder: (context, index) {
              if (index == 0) return SizedBox(height: height * 0.4);
              if (index == lines.length + 1) {
                return SizedBox(height: height * 0.6);
              }
              return _LyricRow(
                index: index - 1,
                line: lines[index - 1],
                currentIndex: _currentIndex,
              );
            },
          ),
        );
      },
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    required this.index,
    required this.line,
    required this.currentIndex,
  });

  final int index;
  final LyricLine line;
  final ValueNotifier<int> currentIndex;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentIndex,
      builder: (context, current, _) {
        final isCurrent = current == index;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => audioHandler.seek(
            // +1ms：跳到最后一行时避免又被判回上一句。
            line.start + const Duration(milliseconds: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isCurrent ? 19 : 16,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                color: isCurrent
                    ? OnlinePalette.primaryLight
                    : OnlinePalette.textDim.withAlpha(150),
              ),
              child: Column(
                children: [
                  Text(line.text),
                  for (final translate in line.translates)
                    Text(
                      translate,
                      style: TextStyle(
                        fontSize: 12,
                        color: OnlinePalette.textFaint,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

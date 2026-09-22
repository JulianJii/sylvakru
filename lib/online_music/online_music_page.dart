// 网络音乐播放界面（全屏）。
//
// 只负责"搜歌 -> 解析直链 -> 交给现有播放引擎播放"，不碰任何本地音乐功能。
// 播放走 `audioHandler`：在线曲目以 `sourceType=.local` + `path=直链` 注入，
// 因此不会有第二个播放器实例，也能拿到系统媒体通知。

import 'dart:async';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_download_panel.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/online_player_detail.dart';
import 'package:sylvakru/online_music/online_search_history.dart';
import 'package:sylvakru/online_music/online_window_drag_area.dart';

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

/// 全屏打开网络音乐播放界面。
///
/// 在线音乐的所有状态都自包含在 `lib/online_music/` 里，调用方只需要这一行。
/// 返回时 pop 掉这条路由，本地界面原样等在下面。
Future<void> openOnlineMusicPage(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          Theme(data: buildOnlineTheme(), child: const OnlineMusicPage()),
    ),
  );
}

class OnlineMusicPage extends StatefulWidget {
  const OnlineMusicPage({super.key});

  @override
  State<OnlineMusicPage> createState() => _OnlineMusicPageState();
}

enum OnlineSearchType { song, playlist }

class _OnlineMusicPageState extends State<OnlineMusicPage> {
  final TextEditingController _keywordController = TextEditingController();

  /// 搜索请求代次号：只接受最后一次发起的结果，丢弃过期响应。
  int _searchGeneration = 0;

  OnlineSearchType _searchType = OnlineSearchType.song;
  List<OnlineTrack> _results = const [];
  List<OnlinePlaylist> _playlistResults = const [];
  OnlinePlaylist? _selectedPlaylist;
  List<OnlineTrack> _playlistTracks = const [];
  bool _loadingPlaylistTracks = false;

  bool _searching = false;
  String? _message;

  String _sourceFilter = 'all';

  /// source -> 可用音质，来自自定义源脚本的 `lx.send('inited')`。
  /// 拿不到就退回歌曲自带的。
  Map<String, List<String>> _apiSources = const {};

  /// 正在解析直链的曲目 id。
  String? _resolvingId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 每次都重读一遍设置（就一个小 JSON），省掉"是否已加载"的全局标志，
  /// 顺带能拿到上次退出后改过的配置。
  Future<void> _bootstrap() async {
    await onlineSettings.load();
    await onlineSearchHistory.load();
    await onlineDownloader.init();
    if (!mounted) return;
    setState(() {});
    await _loadScriptSources();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  /// 跑一遍脚本（或复用已加载的），把脚本声明的音源与音质拿来过滤音质选择。
  Future<void> _loadScriptSources() async {
    if (!onlineSettings.hasScript) return;
    try {
      final sources = await onlineApiClient.fetchSources();
      if (mounted) setState(() => _apiSources = sources);
    } catch (e) {
      logger.output('[online] 自定义源脚本加载失败: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() => _message = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _search() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty || _searching) return;

    // 关键词保存到本地
    onlineSearchHistory.add(keyword);

    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _message = null;
      if (_searchType == OnlineSearchType.playlist) {
        _selectedPlaylist = null;
        _playlistTracks = const [];
      }
    });

    final sources = _sourceFilter == 'all'
        ? onlineSearchers.keys.toList()
        : [_sourceFilter];

    final mergedTracks = <OnlineTrack>[];
    final mergedPlaylists = <OnlinePlaylist>[];
    final failures = <String>[];
    await Future.wait(
      sources.map((source) async {
        final searcher = onlineSearchers[source]!;
        try {
          if (_searchType == OnlineSearchType.song) {
            mergedTracks.addAll(await searcher.search(keyword));
          } else {
            mergedPlaylists.addAll(await searcher.searchPlaylists(keyword));
          }
        } catch (e) {
          // 一个音源挂掉不该拖垮另一个，收集起来一起提示。
          failures.add(
            '${searcher.label}：${e is OnlineApiException ? e.message : e}',
          );
        }
      }),
    );

    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _searching = false;
      if (_searchType == OnlineSearchType.song) {
        _results = mergedTracks;
        _message = failures.isEmpty
            ? null
            : mergedTracks.isEmpty
            ? failures.join('\n')
            : '部分音源不可用 —— ${failures.join('；')}';
      } else {
        _playlistResults = mergedPlaylists;
        _message = failures.isEmpty
            ? null
            : mergedPlaylists.isEmpty
            ? failures.join('\n')
            : '部分音源不可用 —— ${failures.join('；')}';
      }
    });
  }

  Future<void> _openPlaylist(OnlinePlaylist playlist) async {
    setState(() {
      _selectedPlaylist = playlist;
      _playlistTracks = const [];
      _loadingPlaylistTracks = true;
      _message = null;
    });

    final searcher = onlineSearchers[playlist.source];
    if (searcher == null) {
      setState(() => _loadingPlaylistTracks = false);
      _showMessage('未找到对应音源解析器');
      return;
    }

    try {
      final tracks = await searcher.getPlaylistTracks(playlist.id);
      if (!mounted) return;
      setState(() {
        _playlistTracks = tracks;
        _loadingPlaylistTracks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPlaylistTracks = false);
      _showMessage('加载歌单曲目失败：${e is OnlineApiException ? e.message : e}');
    }
  }

  /// 交集：歌曲实际有的音质 ∩ 接口声明的音质。取不到接口声明就用歌曲自带的。
  List<String> _qualitysOf(OnlineTrack track) {
    final declared = _apiSources[track.source];
    final own = track.qualitys;
    if (declared == null || declared.isEmpty) return own;
    return own.where(declared.contains).toList();
  }

  String _qualityFor(OnlineTrack track) {
    final available = _qualitysOf(track);
    if (available.isEmpty) return onlineSettings.quality.value;
    final preferred = onlineSettings.quality.value;
    if (available.contains(preferred)) return preferred;
    return available.first;
  }

  Future<void> _play(OnlineTrack track) async {
    if (_resolvingId != null) return;
    final quality = _qualityFor(track);
    setState(() => _resolvingId = track.id);
    try {
      final url = await onlineApiClient.resolveUrl(
        track: track,
        quality: quality,
      );
      if (!mounted) return;

      final metadata = MyAudioMetadata(
        AudioMetadata(
          format: quality,
          title: track.name,
          artist: track.singer,
          album: track.albumName,
          duration: _parseInterval(track.interval),
        ),
        id: track.id,
        path: url,
      )..parsedLyrics = ParsedLyrics();
      // 网络曲目没有本地封面/歌词文件，提前标记已加载，避免既有引擎去按
      // 假路径读标签（详见 picture_service / lyric.dart 的加载分支）。
      metadata.picture
        ..isLoaded = true
        ..color = Colors.grey;

      // 始终以单首曲目覆盖播放队列：上一首/下一首由界面按当前活跃列表
      // 自行计算（见 [_playRelative]），而不是依赖全局 playQueue 的累积顺序。
      await audioHandler.setPlayQueue([metadata], 0);
      // 播放条和详情页靠它拿封面 / 歌词，元数据里只存了歌名歌手。
      onlineNowPlaying.value = track;
      logger.output('[online] play ${track.source} ${track.name} @$quality');
    } catch (e, stack) {
      logger.output('[online] play failed: $e\n$stack');
      _showMessage(
        '「${track.name}」播放失败：${e is OnlineApiException ? e.message : e}',
      );
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  /// 下载到用户选的目录。没选过就先弹选择器，取消就不再继续。
  Future<void> _download(OnlineTrack track) async {
    if (!onlineDownloader.hasDirectory) {
      final picked = await onlineDownloader.pickDirectory();
      if (picked == null || !mounted) return;
    }
    final error = await onlineDownloader.download(
      track,
      quality: _qualityFor(track),
    );
    if (!mounted || error == null) return;
    _showMessage(error);
  }

  bool get _isViewingPlaylistTracks =>
      _searchType == OnlineSearchType.playlist && _selectedPlaylist != null;

  List<OnlineTrack> get _activeTracks =>
      _isViewingPlaylistTracks ? _playlistTracks : _results;

  /// 当前正在播放的曲目在活跃列表里的下标；不在列表里时返回 -1。
  int get _currentResultIndex {
    final id = currentSongNotifier.value?.id;
    if (id == null) return -1;
    return _activeTracks.indexWhere((track) => track.id == id);
  }

  /// 上一首/下一首：严格在当前列表里按序移动。
  void _playRelative(int delta) {
    final idx = _currentResultIndex;
    if (idx < 0) return;
    final target = idx + delta;
    if (target < 0 || target >= _activeTracks.length) return;
    _play(_activeTracks[target]);
  }

  bool get _canPrevious => _currentResultIndex > 0;

  bool get _canNext =>
      _currentResultIndex >= 0 &&
      _currentResultIndex < _activeTracks.length - 1;

  /// 点播放条向上展开详情页。详情页里的上一首/下一首与播放条同一个口径。
  void _openDetail() {
    openOnlinePlayerDetail(
      context,
      onPrevious: _canPrevious ? () => _playRelative(-1) : null,
      onNext: _canNext ? () => _playRelative(1) : null,
    );
  }

  static Duration _parseInterval(String interval) {
    final parts = interval.split(':');
    if (parts.length != 2) return Duration.zero;
    return Duration(
      minutes: int.tryParse(parts[0]) ?? 0,
      seconds: int.tryParse(parts[1]) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              _buildToolbar(),
              _buildSearchArea(),
              Divider(height: 1, color: OnlinePalette.surfaceAlt),
              Expanded(child: _buildResults()),
              Divider(height: 1, color: OnlinePalette.surfaceAlt),
              _buildPlayerBar(),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 顶部工具栏

  Widget _buildToolbar() {
    // 这一页整屏盖住了主界面，标题栏那块拖动区跟着一起被盖住，所以顶栏自己
    // 要补一套：拖动移动窗口 + 右侧标准窗口按钮（见 online_window_drag_area）。
    return WindowDragArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 5, 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [OnlinePalette.primaryLight, OnlinePalette.primary],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 20,
                color: OnlinePalette.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '在线音乐',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 14),
            const Spacer(),
            const _DownloadIndicator(),
            IconButton(
              tooltip: '音源设置',
              onPressed: _openSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '返回本地音乐',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.home_rounded),
            ),
            WindowControls(color: OnlinePalette.textDim),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 搜索区

  Widget _buildSearchArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _keywordController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: _searchType == OnlineSearchType.song
                  ? '搜索歌曲、歌手、专辑…'
                  : '搜索歌单、标签、主题…',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: OnlinePalette.textFaint,
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _keywordController,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '搜索',
                        icon: const Icon(Icons.search_rounded, size: 18),
                        onPressed: _searching ? null : _search,
                      ),
                      IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _keywordController.clear();
                          setState(() {
                            _results = const [];
                            _playlistResults = const [];
                            _selectedPlaylist = null;
                            _playlistTracks = const [];
                          });
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          _buildSearchHistory(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTypeFilter(),
                      const SizedBox(width: 12),
                      _SourceFilterChips(
                        value: _sourceFilter,
                        onChanged: (value) =>
                            setState(() => _sourceFilter = value),
                      ),
                    ],
                  ),
                ),
              ),
              if (_searchType == OnlineSearchType.song) ...[
                _QualityMenu(
                  valueListenable: onlineSettings.quality,
                  onSelected: (value) {
                    onlineSettings.quality.value = value;
                    onlineSettings.save();
                  },
                ),
                const SizedBox(width: 10),
              ],
              FilledButton(
                onPressed: _searching ? null : _search,
                style: FilledButton.styleFrom(
                  backgroundColor: OnlinePalette.surfaceAlt,
                  foregroundColor: OnlinePalette.text,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                ),
                child: _searching
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: OnlinePalette.primaryLight,
                        ),
                      )
                    : const Text('搜索'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            _MessageBar(
              message: _message!,
              onDismiss: () => setState(() => _message = null),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchHistory() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: onlineSearchHistory.history,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 15,
                      color: OnlinePalette.textFaint,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '历史',
                      style: TextStyle(
                        fontSize: 12,
                        color: OnlinePalette.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final item in list)
                      _HistoryChip(
                        label: item,
                        onTap: () {
                          _keywordController.text = item;
                          _keywordController.selection =
                              TextSelection.fromPosition(
                                TextPosition(offset: item.length),
                              );
                          _search();
                        },
                        onDelete: () => onlineSearchHistory.remove(item),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '清空历史',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: OnlinePalette.textFaint,
                ),
                onPressed: () => onlineSearchHistory.clear(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeFilter() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: OnlinePalette.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeOption(
            label: '歌曲',
            icon: Icons.music_note_rounded,
            selected: _searchType == OnlineSearchType.song,
            onTap: () {
              if (_searchType != OnlineSearchType.song) {
                setState(() {
                  _searchType = OnlineSearchType.song;
                  _selectedPlaylist = null;
                });
                if (_keywordController.text.trim().isNotEmpty) {
                  _search();
                }
              }
            },
          ),
          const SizedBox(width: 2),
          _TypeOption(
            label: '歌单',
            icon: Icons.queue_music_rounded,
            selected: _searchType == OnlineSearchType.playlist,
            onTap: () {
              if (_searchType != OnlineSearchType.playlist) {
                setState(() {
                  _searchType = OnlineSearchType.playlist;
                  _selectedPlaylist = null;
                });
                if (_keywordController.text.trim().isNotEmpty) {
                  _search();
                }
              }
            },
          ),
        ],
      ),
    );
  }

  bool _isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height || !isTooNarrow(context);
  }

  // ---------------------------------------------------------------- 结果列表

  Widget _buildResults() {
    final isLandscape = _isLandscape(context);
    if (_searchType == OnlineSearchType.song) {
      if (_results.isEmpty) {
        return _EmptyState(
          searching: _searching,
          isPlaylist: false,
          hint: !onlineSettings.hasScript
              ? '未导入自定义源：搜索仍可使用，但播放需在「音源设置」里导入洛雪音乐自定义源脚本（.js）'
              : null,
        );
      }
      return ListenableBuilder(
        listenable: currentSongNotifier,
        builder: (context, _) {
          final currentId = currentSongNotifier.value?.id;
          return GridView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 20 : 0,
              vertical: 8,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isLandscape ? 2 : 1,
              mainAxisExtent: 64,
              crossAxisSpacing: 16,
              mainAxisSpacing: 4,
            ),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final track = _results[index];
              return _TrackRow(
                index: index + 1,
                track: track,
                qualityLabel: onlineSettings.quality.value,
                isCurrent: track.id == currentId,
                isResolving: _resolvingId == track.id,
                onTap: () => _play(track),
                onDownload: () => _download(track),
              );
            },
          );
        },
      );
    }

    // 歌单模式
    if (_selectedPlaylist != null) {
      return _buildPlaylistDetailView();
    }

    if (_playlistResults.isEmpty) {
      return _EmptyState(searching: _searching, isPlaylist: true);
    }

    return GridView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 20 : 0,
        vertical: 8,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscape ? 2 : 1,
        mainAxisExtent: 72,
        crossAxisSpacing: 16,
        mainAxisSpacing: 4,
      ),
      itemCount: _playlistResults.length,
      itemBuilder: (context, index) {
        final playlist = _playlistResults[index];
        return _PlaylistRow(
          index: index + 1,
          playlist: playlist,
          onTap: () => _openPlaylist(playlist),
        );
      },
    );
  }

  Widget _buildPlaylistDetailView() {
    final playlist = _selectedPlaylist!;
    final isLandscape = _isLandscape(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          color: OnlinePalette.surface.withAlpha(120),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回歌单列表',
                onPressed: () => setState(() {
                  _selectedPlaylist = null;
                  _playlistTracks = const [];
                }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: playlist.pic.isNotEmpty
                      ? Image.network(
                          playlist.pic,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: OnlinePalette.surfaceAlt,
                            child: Icon(
                              Icons.queue_music_rounded,
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                        )
                      : Container(
                          color: OnlinePalette.surfaceAlt,
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: OnlinePalette.textFaint,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: OnlinePalette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '创建者：${playlist.creator.isEmpty ? '未知' : playlist.creator}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: OnlinePalette.textDim,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          playlist.songCountFormatted,
                          style: TextStyle(
                            fontSize: 12,
                            color: OnlinePalette.textFaint,
                          ),
                        ),
                        if (playlist.playCountFormatted.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            playlist.playCountFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        _Tag(
                          text:
                              onlineSearchers[playlist.source]?.label ??
                              playlist.source,
                          color: OnlinePalette.primaryLight,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: OnlinePalette.surfaceAlt),
        Expanded(
          child: _loadingPlaylistTracks
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: OnlinePalette.primaryLight,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        '正在加载歌单曲目…',
                        style: TextStyle(color: OnlinePalette.textFaint),
                      ),
                    ],
                  ),
                )
              : _playlistTracks.isEmpty
              ? Center(
                  child: Text(
                    '歌单中没有曲目或加载失败',
                    style: TextStyle(color: OnlinePalette.textFaint),
                  ),
                )
              : ListenableBuilder(
                  listenable: currentSongNotifier,
                  builder: (context, _) {
                    final currentId = currentSongNotifier.value?.id;
                    return GridView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 20 : 0,
                        vertical: 8,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isLandscape ? 2 : 1,
                        mainAxisExtent: 64,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: _playlistTracks.length,
                      itemBuilder: (context, index) {
                        final track = _playlistTracks[index];
                        return _TrackRow(
                          index: index + 1,
                          track: track,
                          qualityLabel: onlineSettings.quality.value,
                          isCurrent: track.id == currentId,
                          isResolving: _resolvingId == track.id,
                          onTap: () => _play(track),
                          onDownload: () => _download(track),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 底部播放条

  Widget _buildPlayerBar() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        currentSongNotifier,
        isPlayingNotifier,
        onlineNowPlaying,
      ]),
      builder: (context, _) {
        final song = currentSongNotifier.value;
        // 音量调节仅在横屏下提供，竖屏状态下一律取消
        final size = MediaQuery.sizeOf(context);
        final isLandscape = size.width > size.height;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          color: OnlinePalette.surface,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: song == null ? null : _openDetail,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: song == null
                                ? [OnlinePalette.surfaceAlt, OnlinePalette.bg]
                                : [
                                    OnlinePalette.primaryLight,
                                    OnlinePalette.primary,
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          // 正在播的是本地曲目时不显示在线封面（列表里的那首不算数）。
                          child: OnlineCover(
                            track: onlineNowPlaying.value?.id == song?.id
                                ? onlineNowPlaying.value
                                : null,
                            placeholder: Icon(
                              song == null
                                  ? Icons.music_note_rounded
                                  : Icons.graphic_eq,
                              color: song == null
                                  ? OnlinePalette.textFaint
                                  : OnlinePalette.onPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song == null ? '还没有在播放' : getTitle(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song == null ? '点击搜索结果即可播放' : getArtist(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: '上一首',
                onPressed: _canPrevious ? () => _playRelative(-1) : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: isPlayingNotifier,
                builder: (context, isPlaying, _) {
                  return IconButton.filled(
                    tooltip: isPlaying ? '暂停' : '播放',
                    style: IconButton.styleFrom(
                      backgroundColor: OnlinePalette.primary,
                      foregroundColor: OnlinePalette.onPrimary,
                    ),
                    onPressed: song == null
                        ? null
                        : () => isPlaying
                              ? audioHandler.pause()
                              : audioHandler.play(),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: '下一首',
                onPressed: _canNext ? () => _playRelative(1) : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
              const SizedBox(width: 12),
              if (isLandscape) ...[
                const Expanded(child: OnlineSeekBar()),
                const SizedBox(width: 16),
                Flexible(child: _VolumeControl()),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _SettingsDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// 小组件
// ---------------------------------------------------------------------------

class _SourceFilterChips extends StatelessWidget {
  const _SourceFilterChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = <String, String>{
      'all': '全部',
      for (final searcher in onlineSearchers.values)
        searcher.source: searcher.label,
    };
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in entries.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: value == entry.key,
            onSelected: (_) => onChanged(entry.key),
            showCheckmark: false,
            selectedColor: OnlinePalette.primary.withAlpha(70),
            backgroundColor: OnlinePalette.surfaceAlt,
            side: BorderSide.none,
            labelStyle: TextStyle(
              fontSize: 13,
              color: value == entry.key
                  ? OnlinePalette.onPrimary
                  : OnlinePalette.textDim,
            ),
          ),
      ],
    );
  }
}

class _QualityMenu extends StatelessWidget {
  const _QualityMenu({required this.valueListenable, required this.onSelected});

  final ValueListenable<String> valueListenable;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: valueListenable,
      builder: (context, quality, _) {
        return PopupMenuButton<String>(
          tooltip: '音质',
          initialValue: quality,
          onSelected: onSelected,
          color: OnlinePalette.surfaceAlt,
          itemBuilder: (context) => [
            for (final item in qualityOrder)
              PopupMenuItem<String>(
                value: item,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: item == quality
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: OnlinePalette.primaryLight,
                            )
                          : null,
                    ),
                    Text(item),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: OnlinePalette.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.high_quality_rounded,
                  size: 16,
                  color: OnlinePalette.textDim,
                ),
                const SizedBox(width: 6),
                Text(quality, style: const TextStyle(fontSize: 13)),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: OnlinePalette.textDim,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: OnlinePalette.warn.withAlpha(28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OnlinePalette.warn.withAlpha(70)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: OnlinePalette.warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: OnlinePalette.warn),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            iconSize: 16,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.searching,
    this.isPlaylist = false,
    this.hint,
  });

  final bool searching;
  final bool isPlaylist;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: searching
            ? Column(
                key: ValueKey('loading'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: OnlinePalette.primaryLight,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '正在搜索…',
                    style: TextStyle(color: OnlinePalette.textFaint),
                  ),
                ],
              )
            : Column(
                key: ValueKey(isPlaylist ? 'idle_playlist' : 'idle_song'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPlaylist
                        ? Icons.queue_music_rounded
                        : Icons.travel_explore_rounded,
                    size: 46,
                    color: OnlinePalette.textFaint,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isPlaylist ? '输入关键词搜索歌单' : '输入关键词开始搜索',
                    style: TextStyle(
                      fontSize: 15,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isPlaylist
                        ? '搜索结果来自酷我 / 咪咕歌单，点击歌单可查看曲目并播放'
                        : '搜索结果来自酷我 / 咪咕，播放直链由聚合接口解析',
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      hint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: OnlinePalette.warn,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({
    required this.label,
    required this.onTap,
    required this.onDelete,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: OnlinePalette.surfaceAlt,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: OnlinePalette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: OnlinePalette.surfaceAlt),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: OnlinePalette.textDim),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(10),
              hoverColor: OnlinePalette.text.withAlpha(20),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: OnlinePalette.textFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? OnlinePalette.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? OnlinePalette.onPrimary
                  : OnlinePalette.textFaint,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? OnlinePalette.onPrimary
                    : OnlinePalette.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.index,
    required this.playlist,
    required this.onTap,
  });

  final int index;
  final OnlinePlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: OnlinePalette.surfaceAlt,
          child: Container(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 10, 16, 10),
            decoration: BoxDecoration(
              color: OnlinePalette.surface.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: OnlinePalette.surfaceAlt.withAlpha(80)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: playlist.pic.isNotEmpty
                        ? Image.network(
                            playlist.pic,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: OnlinePalette.surfaceAlt,
                              child: Icon(
                                Icons.queue_music_rounded,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          )
                        : Container(
                            color: OnlinePalette.surfaceAlt,
                            child: Icon(
                              Icons.queue_music_rounded,
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: OnlinePalette.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              playlist.creator.isEmpty
                                  ? '未知作者'
                                  : playlist.creator,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            playlist.songCountFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                          if (!compact &&
                              playlist.playCountFormatted.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              playlist.playCountFormatted,
                              style: TextStyle(
                                fontSize: 12,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Tag(
                  text:
                      onlineSearchers[playlist.source]?.label ??
                      playlist.source,
                  color: OnlinePalette.primaryLight,
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: OnlinePalette.textFaint,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 在线曲目封面。搜索结果里酷我不带封面、咪咕也可能缺，所以这里按 lx-music
/// 的 getPic 口径现取一次（脚本 `pic` action -> 音源接口）。结果由
/// [onlineApiClient] 缓存并去重，同一首歌在多处显示只会请求一次。
class OnlineCover extends StatefulWidget {
  const OnlineCover({
    required this.track,
    this.placeholder,
    this.fit = BoxFit.cover,
    super.key,
  });

  /// 要显示封面的曲目；null 表示当前没有在线曲目，直接显示占位图。
  final OnlineTrack? track;

  /// 没有封面或加载失败时显示什么，不给就什么都不显示。
  final Widget? placeholder;

  final BoxFit fit;

  @override
  State<OnlineCover> createState() => _OnlineCoverState();
}

class _OnlineCoverState extends State<OnlineCover> {
  String _url = '';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant OnlineCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id) {
      _url = '';
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final track = widget.track;
    if (track == null) return;
    final url = await onlineApiClient.fetchPicUrl(track);
    if (!mounted || url.isEmpty || track.id != widget.track?.id) return;
    setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final url = _url.isNotEmpty ? _url : widget.track?.img ?? '';
    if (url.isEmpty) return widget.placeholder ?? const SizedBox.shrink();
    return Image.network(
      url,
      fit: widget.fit,
      errorBuilder: (_, _, _) => widget.placeholder ?? const SizedBox.shrink(),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.qualityLabel,
    required this.isCurrent,
    required this.isResolving,
    required this.onTap,
    required this.onDownload,
  });

  final int index;
  final OnlineTrack track;
  final String qualityLabel;
  final bool isCurrent;
  final bool isResolving;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: OnlinePalette.surfaceAlt,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 10, 16, 10),
            decoration: BoxDecoration(
              color: isCurrent
                  ? OnlinePalette.primary.withAlpha(30)
                  : OnlinePalette.surface.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCurrent
                    ? OnlinePalette.primary.withAlpha(120)
                    : OnlinePalette.surfaceAlt.withAlpha(80),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: isResolving
                      // Center 给宽松约束：否则外层 SizedBox(32) 的紧宽度会把
                      // 转圈压成 32x16 的扁圆。
                      ? Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: OnlinePalette.primaryLight,
                            ),
                          ),
                        )
                      : isCurrent
                      ? Icon(
                          Icons.equalizer_rounded,
                          size: 18,
                          color: OnlinePalette.primaryLight,
                        )
                      : Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 12,
                            color: OnlinePalette.textFaint,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: OnlineCover(
                      track: track,
                      placeholder: Container(
                        color: OnlinePalette.surfaceAlt,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 18,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isCurrent
                              ? OnlinePalette.primaryLight
                              : OnlinePalette.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        compact
                            ? track.singer
                            : '${track.singer} · ${track.albumName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  _Tag(text: qualityLabel, color: OnlinePalette.textFaint),
                  const SizedBox(width: 6),
                  _Tag(
                    text: onlineSearchers[track.source]?.label ?? track.source,
                    color: OnlinePalette.primaryLight,
                  ),
                ],
                const SizedBox(width: 10),
                Text(
                  track.interval,
                  style: TextStyle(
                    fontSize: 12,
                    color: OnlinePalette.textFaint,
                  ),
                ),
                const SizedBox(width: 4),
                _DownloadButton(track: track, onDownload: onDownload),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 行内下载按钮。只订阅自己的曲目，进度刷新不会重建整行。
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.track, required this.onDownload});

  final OnlineTrack track;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<OnlineDownloadEntry>>(
      valueListenable: onlineDownloader.entries,
      builder: (context, _, _) {
        final entry = onlineDownloader.entryOf(track.id);
        final state = entry?.state;
        final done = state == OnlineDownloadState.complete;
        final active = state?.isActive ?? false;
        return IconButton(
          tooltip: '下载到下载目录',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: active ? null : onDownload,
          icon: done
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: OnlinePalette.success,
                )
              : active
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: entry!.progress > 0 ? entry.progress : null,
                    color: OnlinePalette.primaryLight,
                  ),
                )
              : Icon(Icons.download_rounded, color: OnlinePalette.textFaint),
        );
      },
    );
  }
}

/// 工具栏上的下载管理入口，右上角挂进行中的任务数。
class _DownloadIndicator extends StatelessWidget {
  const _DownloadIndicator();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<OnlineDownloadEntry>>(
      valueListenable: onlineDownloader.entries,
      builder: (context, entries, _) {
        final count = entries.where((entry) => entry.state.isActive).length;
        return Badge(
          label: Text('$count'),
          isLabelVisible: count > 0,
          backgroundColor: OnlinePalette.primary,
          textColor: OnlinePalette.onPrimary,
          child: IconButton(
            tooltip: '下载管理',
            onPressed: () => openDownloadPanel(context),
            icon: const Icon(Icons.download_rounded),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: volumeNotifier,
      builder: (context, volume, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 18,
              color: OnlinePalette.textDim,
            ),
            Expanded(
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                onChanged: (value) {
                  volumeNotifier.value = value;
                  audioHandler.setVolume(value);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool _importing = false;

  /// 已导入脚本声明了哪些音源，导入/移除后重建。
  late Future<Map<String, List<String>>> _sourcesFuture;

  @override
  void initState() {
    super.initState();
    _sourcesFuture = _refreshSources();
  }

  /// 一个脚本都没有就别去跑引擎了，否则这个 future 的异常没人接。
  Future<Map<String, List<String>>> _refreshSources() =>
      onlineSettings.hasScript
      ? onlineApiClient.fetchSources()
      : Future.value(const <String, List<String>>{});

  /// 填入脚本链接，下载正文后追加进列表并重新加载。同链接会替换原条目。
  Future<void> _importScript() async {
    if (_importing) return;
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const _ScriptUrlDialog(),
    );
    if (url == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final script = await onlineApiClient.fetchScript(url);
      await onlineSettings.addScript(
        LxScriptEntry(name: _scriptNameFromUrl(url), url: url, script: script),
      );
      await onlineApiClient.reload();
      if (!mounted) return;
      // 箭头函数会把赋值结果（Future）当返回值，setState 会直接报错。
      setState(() {
        _sourcesFuture = _refreshSources();
      });
    } catch (e) {
      logger.output('[online] 导入脚本失败: $e');
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 链接末段当脚本名（`xxx/lx-source.js` -> `lx-source.js`），没有就退回域名。
  String _scriptNameFromUrl(String url) {
    final uri = Uri.parse(url);
    return uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
  }

  /// 按列表位置移除；列表顺序就是取链优先级。
  Future<void> _removeScript(int index) async {
    await onlineSettings.removeScript(index);
    await onlineApiClient.reload();
    if (!mounted) return;
    setState(() {
      _sourcesFuture = _refreshSources();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: OnlinePalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '音源设置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '播放直链由洛雪音乐的「自定义源」脚本解析，可导入多个 .js 脚本链接；'
                '按顺序依次取链，一个失败自动用下一个。',
                style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
              ),
              const SizedBox(height: 14),
              Flexible(child: _buildScriptArea()),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: OnlinePalette.primary,
                  foregroundColor: OnlinePalette.onPrimary,
                ),
                onPressed: _importing ? null : _importScript,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('导入脚本'),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: OnlinePalette.surfaceAlt),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '下载目录',
                    style: TextStyle(
                      fontSize: 13,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: onlineSettings.downloadDir,
                      builder: (context, _, _) => Text(
                        onlineDownloader.directoryDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onlineDownloader.pickDirectory(),
                    child: const Text('选择'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '默认音质',
                    style: TextStyle(
                      fontSize: 13,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _QualityMenu(
                    valueListenable: onlineSettings.quality,
                    onSelected: (value) {
                      onlineSettings.quality.value = value;
                      onlineSettings.save();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 列出已导入的脚本与它们声明的音源。脚本声明在加载后才拿得到，
  /// 所以顺手触发一次加载。
  Widget _buildScriptArea() {
    return ValueListenableBuilder<List<LxScriptEntry>>(
      valueListenable: onlineSettings.scripts,
      builder: (context, scripts, _) {
        if (scripts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '还没有自定义源脚本，请填入脚本链接导入',
                style: TextStyle(color: OnlinePalette.textFaint),
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: scripts.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) =>
                    _buildScriptTile(scripts[index], index),
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, List<String>>>(
              future: _sourcesFuture,
              builder: (context, snapshot) => Text(
                _sourcesText(snapshot),
                style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScriptTile(LxScriptEntry entry, int index) {
    return Container(
      decoration: BoxDecoration(
        color: OnlinePalette.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.javascript_rounded, size: 18),
        title: Text(
          '${index + 1}. ${entry.name}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: entry.url.isEmpty
            ? null
            : Text(
                entry.url,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: OnlinePalette.textFaint),
              ),
        trailing: IconButton(
          tooltip: '移除',
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: () => _removeScript(index),
        ),
      ),
    );
  }

  /// 「已声明音源 / 哪个脚本挂了」那一行。
  String _sourcesText(AsyncSnapshot<Map<String, List<String>>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return '正在加载脚本…';
    if (snapshot.hasError) return '脚本加载失败：${snapshot.error}';
    final sources = snapshot.data ?? const {};
    final failures = lxJsSources.failures;
    if (sources.isEmpty && failures.isEmpty) return '脚本没有声明可用的音源';
    return [
      if (sources.isNotEmpty) '已声明音源：${sources.keys.join('、')}（按顺序依次取链）',
      ...failures,
    ].join('\n');
  }
}

/// 输入自定义源脚本的下载链接。
class _ScriptUrlDialog extends StatefulWidget {
  const _ScriptUrlDialog();

  @override
  State<_ScriptUrlDialog> createState() => _ScriptUrlDialogState();
}

class _ScriptUrlDialogState extends State<_ScriptUrlDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OnlinePalette.surface,
      title: const Text('导入自定义源脚本'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          hintText: 'https://example.com/lx-source.js',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('导入')),
      ],
    );
  }
}

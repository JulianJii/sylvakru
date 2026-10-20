// 网络音乐播放界面（全屏）。
//
// 只负责"搜歌 -> 解析直链 -> 交给现有播放引擎播放"，不碰任何本地音乐功能。
// 播放走 `audioHandler`：在线曲目以 `sourceType=.local` + `path=直链` 注入，
// 因此不会有第二个播放器实例，也能拿到系统媒体通知。
//
// 搜索状态与逻辑在 online_search_controller.dart，叶子组件在 widgets/，
// 本文件只做组装、播放/下载副作用与弹窗调度。

import 'dart:async';

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/online_music/online_cache.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/online_play_order.dart';
import 'package:sylvakru/online_music/online_player_detail.dart';
import 'package:sylvakru/online_music/online_search_controller.dart';
import 'package:sylvakru/online_music/online_search_history.dart';
import 'package:sylvakru/online_music/online_window_drag_area.dart';
import 'package:sylvakru/online_music/theme/online_theme.dart';
import 'package:sylvakru/online_music/widgets/online_notice.dart';
import 'package:sylvakru/online_music/widgets/online_page_widgets.dart';
import 'package:sylvakru/online_music/widgets/online_settings_dialog.dart';

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

class _OnlineMusicPageState extends State<OnlineMusicPage> {
  late final OnlineSearchController _controller;

  /// 结果列表共用一个滚动控制权：切换视图（歌曲 / 歌单 / 歌单曲目）时列表
  /// 会换一个 [ValueKey]，位置自然回到顶部，不需要手动 jumpTo。
  final ScrollController _scrollController = ScrollController();

  /// 正在解析直链的曲目 id。
  String? _resolvingId;

  @override
  void initState() {
    super.initState();
    _controller = OnlineSearchController(onMessage: _showMessage);
    _controller.bootstrap();
  }

  @override
  void dispose() {
    // 页面走了就不再接管换曲，回到播放器自己的队列逻辑。
    playQueueSkipHandler = null;
    _scrollController.dispose();
    _controller.dispose();
    // 页面走了就别把通知留在上一层界面上。
    dismissOnlineNotice();
    super.dispose();
  }

  /// 提示统一从这里走：顶部往下滑出一条，几秒后自动收回。
  void _showMessage(String message) {
    if (!mounted) return;
    showOnlineNotice(context, message);
  }

  /// 页面左右留白。窄窗收紧到 16，宽窗 24。
  double get _gutter => OnlineLayout.gutter(MediaQuery.sizeOf(context).width);

  // -------------------------------------------------------------- 播放 / 下载

  /// 点播放条向上展开详情页。详情页里的上一首/下一首与播放条同一个口径。
  void _openDetail() {
    openOnlinePlayerDetail(
      context,
      onPrevious: _canPrevious ? () => _playRelative(-1) : null,
      onNext: _canNext ? () => _playRelative(1) : null,
    );
  }

  bool get _isViewingPlaylistTracks =>
      _controller.searchType == OnlineSearchType.playlist &&
      _controller.selectedPlaylist != null;

  List<OnlineTrack> get _activeTracks => _isViewingPlaylistTracks
      ? _controller.playlistTracks
      : _controller.results;

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

  /// 播完 / 通知栏切歌：按当前播放模式在活跃列表里换一首。
  /// 返回 false 时交回默认逻辑（当前曲不在列表里或列表为空）。
  Future<bool> _skipInActiveList(int delta) async {
    final tracks = _activeTracks;
    final idx = _currentResultIndex;
    if (idx < 0 || tracks.isEmpty) return false;
    final next = onlineNextIndex(
      idx,
      tracks.length,
      playModeNotifier.value,
      delta,
    );
    await _play(tracks[next]);
    return true;
  }

  /// 在线页只改播放模式，不动全局队列：`changePlayMode` 会洗牌 / 还原
  /// 本地队列，而这个队列里只有当前这首在线曲目。
  void _changePlayMode(int mode) {
    if (mode == playModeNotifier.value) return;
    playModeNotifier.value = mode;
    audioHandler.savePlayState();
  }

  Future<void> _play(OnlineTrack track) async {
    if (_resolvingId != null) return;
    final quality = _controller.qualityFor(track);
    setState(() => _resolvingId = track.id);
    try {
      // 命中缓存直接播本地文件，省掉跑脚本解析直链这一步。
      final cached = onlineCache.lookup(track, quality);
      final url =
          cached?.path ??
          await onlineApiClient.resolveUrl(track: track, quality: quality);
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
      // 自行计算（见 [_playRelative] / [_skipInActiveList]），而不是依赖全局
      // playQueue 的累积顺序。targetIndex 用来避开 setPlayQueue 把播放模式
      // 重置成列表循环。
      await audioHandler.setPlayQueue(
        [metadata],
        playModeNotifier.value,
        targetIndex: 0,
      );
      // 播完的自动换曲交给 [_skipInActiveList]：单曲队列里 skipToNext
      // 取模只会原地打转。
      playQueueSkipHandler = _skipInActiveList;
      // 播放条和详情页靠它拿封面 / 歌词，元数据里只存了歌名歌手。
      onlineNowPlaying.value = track;
      // 未命中缓存就边播边落盘，下次直接读本地文件；不阻塞播放。
      if (cached == null) unawaited(onlineCache.store(track, quality, url));
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
      quality: _controller.qualityFor(track),
    );
    if (!mounted || error == null) return;
    _showMessage(error);
  }

  static Duration _parseInterval(String interval) {
    final parts = interval.split(':');
    if (parts.length != 2) return Duration.zero;
    return Duration(
      minutes: int.tryParse(parts[0]) ?? 0,
      seconds: int.tryParse(parts[1]) ?? 0,
    );
  }

  // ---------------------------------------------------------------------- 组装

  @override
  Widget build(BuildContext context) {
    final gutter = _gutter;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
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
                _buildToolbar(gutter),
                Expanded(
                  child: Column(
                    children: [
                      // 搜索区 / 结果区限宽居中，超宽窗口不会把内容拉到贴边。
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: OnlineLayout.maxContentWidth,
                          ),
                          child: _buildSearchArea(gutter),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: OnlineLayout.maxContentWidth,
                            ),
                            child: _buildResults(gutter),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPlayerBar(gutter),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 顶部工具栏

  Widget _buildToolbar(double gutter) {
    // 这一页整屏盖住了主界面，标题栏那块拖动区跟着一起被盖住，所以顶栏自己
    // 要补一套：拖动移动窗口 + 右侧标准窗口按钮（见 online_window_drag_area）。
    return WindowDragArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 16, 8, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [OnlinePalette.primaryLight, OnlinePalette.primary],
                ),
                borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 20,
                color: OnlinePalette.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '在线音乐',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OnlineText.pageTitle,
              ),
            ),
            const DownloadIndicator(),
            IconButton(
              tooltip: '设置',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
            ),
            IconButton(
              tooltip: '返回本地音乐',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.home_rounded),
            ),
            // 与窗口按钮隔开一点，避免误点关闭。
            const SizedBox(width: 8),
            WindowControls(color: OnlinePalette.textDim),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 搜索区

  Widget _buildSearchArea(double gutter) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller.keywordController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _controller.search(),
            style: OnlineText.title.copyWith(
              fontWeight: FontWeight.w400,
              color: OnlinePalette.text,
            ),
            decoration: InputDecoration(
              hintText: _controller.searchType == OnlineSearchType.song
                  ? '搜索歌曲、歌手、专辑…'
                  : '搜索歌单、标签、主题…',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: OnlinePalette.textFaint,
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller.keywordController,
                builder: (context, value, _) {
                  // 搜索中就地把搜索按钮换成转圈，不用等结果区才看得出来。
                  if (_controller.searching) {
                    return Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: OnlinePalette.primaryLight,
                        ),
                      ),
                    );
                  }
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '搜索',
                        icon: const Icon(Icons.search_rounded, size: 18),
                        onPressed: _controller.search,
                      ),
                      IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _controller.clearResults,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          _buildSearchHistory(),
          const SizedBox(height: 10),
          // Wrap 而不是横向滚动行：窄窗时音质自己换行，不会互相挤压。
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildTypeFilter(),
              SourceFilterSelect(
                value: _controller.sourceFilter,
                allowed: _controller.availableSources,
                onChanged: _controller.setSourceFilter,
              ),
              if (_controller.searchType == OnlineSearchType.song)
                QualityMenu(
                  valueListenable: onlineSettings.quality,
                  onSelected: (value) {
                    onlineSettings.quality.value = value;
                    onlineSettings.save();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 搜索历史：单行横向滚动，条数多了不会把搜索区顶高。
  Widget _buildSearchHistory() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: onlineSearchHistory.history,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 15,
                color: OnlinePalette.textFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = list[index];
                      return HistoryChip(
                        label: item,
                        onTap: () {
                          _controller.keywordController.text = item;
                          _controller.keywordController.selection =
                              TextSelection.fromPosition(
                                TextPosition(offset: item.length),
                              );
                          _controller.search();
                        },
                        onDelete: () => onlineSearchHistory.remove(item),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
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
        borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TypeOption(
            label: '歌曲',
            icon: Icons.music_note_rounded,
            selected: _controller.searchType == OnlineSearchType.song,
            onTap: () => _switchType(OnlineSearchType.song),
          ),
          const SizedBox(width: 2),
          TypeOption(
            label: '歌单',
            icon: Icons.queue_music_rounded,
            selected: _controller.searchType == OnlineSearchType.playlist,
            onTap: () => _switchType(OnlineSearchType.playlist),
          ),
        ],
      ),
    );
  }

  void _switchType(OnlineSearchType type) {
    if (_controller.searchType == type) return;
    _controller.setSearchType(type);
    if (_controller.keywordController.text.trim().isNotEmpty) {
      _controller.search();
    }
  }

  // ---------------------------------------------------------------- 结果列表

  Widget _buildResults(double gutter) {
    if (_controller.searchType == OnlineSearchType.song) {
      final results = _controller.results;
      if (results.isEmpty) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: EmptyState(
            searching: _controller.searching,
            isPlaylist: false,
            hint: !onlineSettings.hasScript
                ? '未导入自定义源：搜索仍可使用，但播放需在「音源设置」里导入洛雪音乐自定义源脚本（.js）'
                : null,
          ),
        );
      }
      return ListenableBuilder(
        listenable: currentSongNotifier,
        builder: (context, _) {
          final currentId = currentSongNotifier.value?.id;
          return _buildGrid(
            viewKey: 'songs',
            gutter: gutter,
            rowHeight: OnlineLayout.trackRowHeight,
            itemCount: results.length,
            hasMore: _controller.songHasMore,
            onLoadMore: _controller.loadMoreSongs,
            itemBuilder: (context, index) {
              final track = results[index];
              return TrackRow(
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
    if (_controller.selectedPlaylist != null) {
      return _buildPlaylistDetailView(gutter);
    }

    final playlistResults = _controller.playlistResults;
    if (playlistResults.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: EmptyState(searching: _controller.searching, isPlaylist: true),
      );
    }

    return _buildGrid(
      viewKey: 'playlists',
      gutter: gutter,
      rowHeight: OnlineLayout.playlistRowHeight,
      itemCount: playlistResults.length,
      hasMore: _controller.playlistHasMore,
      onLoadMore: _controller.loadMorePlaylists,
      itemBuilder: (context, index) {
        final playlist = playlistResults[index];
        return PlaylistRow(
          index: index + 1,
          playlist: playlist,
          onTap: () => _controller.openPlaylist(playlist),
        );
      },
    );
  }

  /// 结果网格：列数由 [SliverGridDelegateWithMaxCrossAxisExtent] 按可用宽度
  /// 推导（手机 1 列、1050 宽窗口 2 列、再宽 3 列），页脚单独一个 sliver
  /// 占满整行 —— 以前把页脚当成最后一个网格项，2 列时只占半行。
  Widget _buildGrid({
    required String viewKey,
    required double gutter,
    required double rowHeight,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    required bool hasMore,
    required VoidCallback onLoadMore,
  }) {
    return NotificationListener<ScrollNotification>(
      // pixels > 0：结果还没占满一屏时不自动翻页，免得首屏自己连拉好几页。
      onNotification: (notification) {
        if (notification.metrics.pixels > 0 &&
            notification.metrics.extentAfter < 400) {
          onLoadMore();
        }
        return false;
      },
      child: CustomScrollView(
        // 换视图（歌曲 / 歌单 / 歌单曲目）时换一个 key，列表重新挂载、回到顶部。
        key: ValueKey(viewKey),
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: OnlineLayout.gridMaxExtent,
                // 行高固定，但要跟着系统字号放大，否则大字号下两行文字会溢出。
                mainAxisExtent:
                    rowHeight *
                    MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.5),
                crossAxisSpacing: 12,
                mainAxisSpacing: 6,
              ),
              delegate: SliverChildBuilderDelegate(
                itemBuilder,
                childCount: itemCount,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ListFooter(hasMore: hasMore, onLoadMore: onLoadMore),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistDetailView(double gutter) {
    final playlist = _controller.selectedPlaylist!;
    final creator = playlist.creator.isEmpty ? '未知' : playlist.creator;
    return Column(
      children: [
        Container(
          // 返回按钮自带宽内边距，左内边距减 8 让封面与下面的曲目行对齐。
          padding: EdgeInsets.fromLTRB(gutter - 8, 4, gutter, 12),
          decoration: BoxDecoration(
            color: OnlinePalette.surface.withAlpha(140),
            border: Border(bottom: BorderSide(color: OnlinePalette.cardBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回歌单列表',
                onPressed: _controller.closePlaylist,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(OnlineLayout.radiusCard),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: playlist.pic.isNotEmpty
                      ? Image.network(
                          playlist.pic,
                          fit: BoxFit.cover,
                          frameBuilder: fadeInFrame,
                          errorBuilder: (_, _, _) =>
                              _playlistCoverPlaceholder(),
                        )
                      : _playlistCoverPlaceholder(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OnlineText.dialogTitle.copyWith(
                        color: OnlinePalette.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '创建者：$creator',
                          style: OnlineText.caption.copyWith(
                            color: OnlinePalette.textDim,
                          ),
                        ),
                        Text(
                          playlist.songCountFormatted,
                          style: OnlineText.caption.copyWith(
                            color: OnlinePalette.textFaint,
                          ),
                        ),
                        if (playlist.playCountFormatted.isNotEmpty)
                          Text(
                            playlist.playCountFormatted,
                            style: OnlineText.caption.copyWith(
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                        OnlineTag(
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
        Expanded(
          child: _controller.loadingPlaylistTracks
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
                      const SizedBox(height: 16),
                      Text(
                        '正在加载歌单曲目…',
                        style: OnlineText.body.copyWith(
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ],
                  ),
                )
              : _controller.playlistTracks.isEmpty
              ? Center(
                  child: Text(
                    '歌单中没有曲目或加载失败',
                    style: OnlineText.body.copyWith(
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                )
              : ListenableBuilder(
                  listenable: currentSongNotifier,
                  builder: (context, _) {
                    final currentId = currentSongNotifier.value?.id;
                    final tracks = _controller.playlistTracks;
                    return _buildGrid(
                      // 换歌单时也要回到顶部，所以 id 进 key。
                      viewKey: 'tracks:${playlist.id}',
                      gutter: gutter,
                      rowHeight: OnlineLayout.trackRowHeight,
                      itemCount: tracks.length,
                      hasMore: _controller.playlistTrackHasMore,
                      onLoadMore: _controller.loadMorePlaylistTracks,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return TrackRow(
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

  Widget _playlistCoverPlaceholder() {
    return Container(
      color: OnlinePalette.surfaceAlt,
      child: Icon(
        Icons.queue_music_rounded,
        size: 26,
        color: OnlinePalette.textFaint,
      ),
    );
  }

  // ---------------------------------------------------------------- 底部播放条

  Widget _buildPlayerBar(double gutter) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        currentSongNotifier,
        isPlayingNotifier,
        onlineNowPlaying,
      ]),
      builder: (context, _) {
        final song = currentSongNotifier.value;
        return Material(
          color: OnlinePalette.surface,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: OnlinePalette.cardBorder)),
            ),
            // 外层 SafeArea 已经让出底部安全区，这里不再套第二层。
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OnlineLayout.maxContentWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 进度条独占一行：以前和信息、按钮挤在同一个 Row 里，
                      // 窄窗下会被压成十几像素。
                      const OnlineSeekBar(),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 620;
                          final info = _buildNowPlaying(song);
                          if (compact) {
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: info),
                                    const VolumeButton(),
                                  ],
                                ),
                                _buildControls(
                                  iconSize: 24,
                                  playSize: 28,
                                  showVolume: false,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(flex: 3, child: info),
                              const SizedBox(width: 12),
                              _buildControls(
                                iconSize: 28,
                                playSize: 32,
                                showVolume: true,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 播放条左侧的当前曲目信息，点一下展开详情页。
  Widget _buildNowPlaying(MyAudioMetadata? song) {
    // 正在播的是本地曲目时不显示在线封面（列表里的那首不算数）。
    final online = onlineNowPlaying.value?.id == song?.id
        ? onlineNowPlaying.value
        : null;
    return InkWell(
      onTap: song == null ? null : _openDetail,
      borderRadius: BorderRadius.circular(OnlineLayout.radiusCard),
      hoverColor: OnlinePalette.hover,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: song == null
                      ? [OnlinePalette.surfaceAlt, OnlinePalette.bg]
                      : [OnlinePalette.primaryLight, OnlinePalette.primary],
                ),
                borderRadius: BorderRadius.circular(OnlineLayout.radiusCard),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(OnlineLayout.radiusCard),
                child: OnlineCover(
                  track: online,
                  placeholder: Icon(
                    song == null ? Icons.music_note_rounded : Icons.graphic_eq,
                    color: song == null
                        ? OnlinePalette.textFaint
                        : OnlinePalette.onPrimary,
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
                    song == null ? '还没有在播放' : getTitle(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnlineText.title.copyWith(color: OnlinePalette.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song == null ? '点击搜索结果即可播放' : getArtist(song),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnlineText.caption.copyWith(
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 播放条右侧控制组：播放顺序 / 上一首 / 播放 / 下一首 /（宽窗）音量。
  Widget _buildControls({
    required double iconSize,
    required double playSize,
    required bool showVolume,
  }) {
    final padding = EdgeInsets.all(iconSize <= 24 ? 6 : 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放顺序：与本地音乐同一套设置，只是不改全局队列。
        PlayOrderButton(iconSize: iconSize, onModeChange: _changePlayMode),
        IconButton(
          tooltip: '上一首',
          onPressed: _canPrevious ? () => _playRelative(-1) : null,
          iconSize: iconSize,
          style: IconButton.styleFrom(padding: padding),
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
                padding: const EdgeInsets.all(12),
              ),
              iconSize: playSize,
              onPressed: currentSongNotifier.value == null
                  ? null
                  : () => isPlaying
                        ? audioHandler.pause()
                        : audioHandler.play(),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            );
          },
        ),
        IconButton(
          tooltip: '下一首',
          onPressed: _canNext ? () => _playRelative(1) : null,
          iconSize: iconSize,
          style: IconButton.styleFrom(padding: padding),
          icon: const Icon(Icons.skip_next_rounded),
        ),
        if (showVolume) const VolumeButton(),
      ],
    );
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const SettingsDialog(),
    );
    // 里面可能换了生效的脚本（或删了脚本），音源列表得跟着重算。
    if (mounted) await _controller.loadScriptSources();
  }
}

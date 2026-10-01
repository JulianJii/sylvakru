// 网络音乐播放界面（全屏）。
//
// 只负责"搜歌 -> 解析直链 -> 交给现有播放引擎播放"，不碰任何本地音乐功能。
// 播放走 `audioHandler`：在线曲目以 `sourceType=.local` + `path=直链` 注入，
// 因此不会有第二个播放器实例，也能拿到系统媒体通知。
//
// 搜索状态与逻辑在 online_search_controller.dart，叶子组件在 widgets/，
// 本文件只做组装、播放/下载副作用与弹窗调度。

import 'package:audio_tags_lofty/audio_tags_lofty.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/my_audio_metadata.dart';
import 'package:sylvakru/base/services/lyric.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/utils/media_query.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
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

  bool _isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height || !isTooNarrow(context);
  }

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

  List<OnlineTrack> get _activeTracks =>
      _isViewingPlaylistTracks ? _controller.playlistTracks : _controller.results;

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

  Future<void> _play(OnlineTrack track) async {
    if (_resolvingId != null) return;
    final quality = _controller.qualityFor(track);
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
            const DownloadIndicator(),
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
            controller: _controller.keywordController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _controller.search(),
            style: const TextStyle(fontSize: 15),
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
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '搜索',
                        icon: const Icon(Icons.search_rounded, size: 18),
                        onPressed: _controller.searching
                            ? null
                            : _controller.search,
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
                      SourceFilterSelect(
                        value: _controller.sourceFilter,
                        allowed: _controller.availableSources,
                        onChanged: _controller.setSourceFilter,
                      ),
                    ],
                  ),
                ),
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
                      HistoryChip(
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

  Widget _buildResults() {
    final isLandscape = _isLandscape(context);
    if (_controller.searchType == OnlineSearchType.song) {
      final results = _controller.results;
      if (results.isEmpty) {
        return EmptyState(
          searching: _controller.searching,
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
          return NotificationListener<ScrollNotification>(
            // pixels > 0：结果还没占满一屏时不自动翻页，免得首屏自己连拉好几页。
            onNotification: (notification) {
              if (notification.metrics.pixels > 0 &&
                  notification.metrics.extentAfter < 400) {
                _controller.loadMoreSongs();
              }
              return false;
            },
            child: GridView.builder(
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
              itemCount: results.length + 1,
              itemBuilder: (context, index) {
                if (index >= results.length) {
                  return ListFooter(
                    hasMore: _controller.songHasMore,
                    onLoadMore: _controller.loadMoreSongs,
                  );
                }
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
            ),
          );
        },
      );
    }

    // 歌单模式
    if (_controller.selectedPlaylist != null) {
      return _buildPlaylistDetailView();
    }

    final playlistResults = _controller.playlistResults;
    if (playlistResults.isEmpty) {
      return EmptyState(searching: _controller.searching, isPlaylist: true);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels > 0 &&
            notification.metrics.extentAfter < 400) {
          _controller.loadMorePlaylists();
        }
        return false;
      },
      child: GridView.builder(
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
        itemCount: playlistResults.length + 1,
        itemBuilder: (context, index) {
          if (index >= playlistResults.length) {
            return ListFooter(
              hasMore: _controller.playlistHasMore,
              onLoadMore: _controller.loadMorePlaylists,
            );
          }
          final playlist = playlistResults[index];
          return PlaylistRow(
            index: index + 1,
            playlist: playlist,
            onTap: () => _controller.openPlaylist(playlist),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistDetailView() {
    final playlist = _controller.selectedPlaylist!;
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
                onPressed: _controller.closePlaylist,
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
        Divider(height: 1, color: OnlinePalette.surfaceAlt),
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
                      SizedBox(height: 16),
                      Text(
                        '正在加载歌单曲目…',
                        style: TextStyle(color: OnlinePalette.textFaint),
                      ),
                    ],
                  ),
                )
              : _controller.playlistTracks.isEmpty
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
                    final tracks = _controller.playlistTracks;
                    return NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.pixels > 0 &&
                            notification.metrics.extentAfter < 400) {
                          _controller.loadMorePlaylistTracks();
                        }
                        return false;
                      },
                      child: GridView.builder(
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
                        itemCount: tracks.length + 1,
                        itemBuilder: (context, index) {
                          if (index >= tracks.length) {
                            return ListFooter(
                              hasMore: _controller.playlistTrackHasMore,
                              onLoadMore: _controller.loadMorePlaylistTracks,
                            );
                          }
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
                      ),
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
        // 横屏空间充裕，把播放控制按钮放大，方便点击。
        final isLandscape = _isLandscape(context);
        final controlIconSize = isLandscape ? 34.0 : 24.0;
        final controlPadding = EdgeInsets.all(isLandscape ? 14 : 8);
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
              // 中间：进度条（与详情页共用一个组件）。
              const Expanded(flex: 2, child: OnlineSeekBar()),
              const SizedBox(width: 16),
              // 右侧：上一首 / 播放 / 下一首。
              IconButton(
                tooltip: '上一首',
                onPressed: _canPrevious ? () => _playRelative(-1) : null,
                iconSize: controlIconSize,
                style: IconButton.styleFrom(padding: controlPadding),
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
                      padding: controlPadding,
                    ),
                    iconSize: controlIconSize,
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
                iconSize: controlIconSize,
                style: IconButton.styleFrom(padding: controlPadding),
                icon: const Icon(Icons.skip_next_rounded),
              ),
              const SizedBox(width: 8),
              // 最右：音量按钮，点击弹出音量条。
              const VolumeButton(),
            ],
          ),
        );
      },
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

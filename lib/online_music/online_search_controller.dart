// 在线音乐页的搜索状态与逻辑：搜索词、搜索结果、歌单、分页、音源。
//
// 从 online_music_page.dart 的巨型 State 里抽出来。页面只负责组装视图与
// 播放/下载等副作用，搜索相关的状态变更都在这里，通过 [ChangeNotifier] 通知。

import 'package:material_ui/material_ui.dart';

import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/online_search_history.dart';

/// 歌单曲目每页条数。歌单详情接口不给总数，有没有下一页就看这一页满没满。
const int _playlistTrackPageSize = 50;

enum OnlineSearchType { song, playlist }

class OnlineSearchController extends ChangeNotifier {
  OnlineSearchController({required this.onMessage});

  /// 出错/提示的统一出口，由页面接到顶部通知上。
  final void Function(String message) onMessage;

  final TextEditingController keywordController = TextEditingController();

  OnlineSearchType searchType = OnlineSearchType.song;
  List<OnlineTrack> results = const [];
  List<OnlinePlaylist> playlistResults = const [];
  OnlinePlaylist? selectedPlaylist;
  List<OnlineTrack> playlistTracks = const [];
  bool loadingPlaylistTracks = false;

  /// 歌曲搜索结果分页。单选音源：这一页有没有下一页就看本页是否返回了结果。
  int songPage = 1;
  bool songHasMore = false;
  bool songLoadingMore = false;

  /// 歌单搜索结果分页。
  int playlistPage = 1;
  bool playlistHasMore = false;
  bool playlistLoadingMore = false;

  /// 歌单曲目（详情页）分页。
  int playlistTrackPage = 1;
  bool playlistTrackHasMore = false;
  bool playlistTrackLoadingMore = false;

  /// 搜索请求代次号：只接受最后一次发起的结果，丢弃过期响应。
  int _searchGeneration = 0;

  /// 歌单曲目请求代次号：换歌单后丢弃上一个歌单在途的分页请求。
  int _playlistTrackGeneration = 0;

  bool searching = false;

  /// 当前选中的音源（单选）。默认酷我，用户切换后持久化。
  String sourceFilter = 'kw';

  /// source -> 可用音质，来自自定义源脚本的 `lx.send('inited')`。
  /// 拿不到就退回歌曲自带的。
  Map<String, List<String>> apiSources = const {};

  bool _disposed = false;

  /// 每次都重读一遍设置（就一个小 JSON），省掉"是否已加载"的全局标志，
  /// 顺带能拿到上次退出后改过的配置。
  Future<void> bootstrap() async {
    await onlineSettings.load();
    await onlineSearchHistory.load();
    await onlineDownloader.init();
    // 恢复上次选中的音源；设置里存了已下线的源就退回酷我。
    final source = onlineSettings.source.value;
    sourceFilter = onlineSearchers.containsKey(source) ? source : 'kw';
    if (_disposed) return;
    notifyListeners();
    await loadScriptSources();
  }

  /// 下拉里显示的源：脚本声明了哪些源就只显示哪些（脚本不支持的搜到也
  /// 播不了）；没导入脚本或还没加载完时显示全部搜索源。
  List<String> get availableSources {
    if (apiSources.isEmpty) return onlineSearchers.keys.toList();
    return [
      for (final source in onlineSearchers.keys)
        if (apiSources.containsKey(source)) source,
    ];
  }

  /// 跑一遍脚本（或复用已加载的），把脚本声明的音源与音质拿来过滤
  /// 音质选择与音源下拉。
  Future<void> loadScriptSources() async {
    if (!onlineSettings.hasScript) return;
    try {
      final sources = await onlineApiClient.fetchSources();
      if (_disposed) return;
      apiSources = sources;
      // 上次选的源这次脚本不支持了，退到第一个可用源。
      if (sources.isNotEmpty && !sources.containsKey(sourceFilter)) {
        final fallback = availableSources.first;
        sourceFilter = fallback;
        onlineSettings.source.value = fallback;
        onlineSettings.save();
      }
      notifyListeners();
    } catch (e) {
      logger.output('[online] 自定义源脚本加载失败: $e');
    }
  }

  /// 当前选中的搜索器。
  OnlineSearcher get activeSearcher => onlineSearchers[sourceFilter]!;

  void _resetSongPaging() {
    songPage = 1;
    songHasMore = false;
    songLoadingMore = false;
  }

  void _resetPlaylistPaging() {
    playlistPage = 1;
    playlistHasMore = false;
    playlistLoadingMore = false;
  }

  void _resetPlaylistTrackPaging() {
    playlistTrackPage = 1;
    playlistTrackHasMore = false;
    playlistTrackLoadingMore = false;
  }

  /// 切换搜索类型（歌曲 / 歌单），并清掉当前歌单详情。
  void setSearchType(OnlineSearchType type) {
    if (searchType == type) return;
    searchType = type;
    selectedPlaylist = null;
    notifyListeners();
  }

  /// 切换音源：立刻用新音源重搜一次。
  Future<void> setSourceFilter(String value) async {
    if (value == sourceFilter) return;
    sourceFilter = value;
    onlineSettings.source.value = value;
    onlineSettings.save();
    notifyListeners();
    await search();
  }

  /// 清空关键词与全部结果（清空按钮）。
  void clearResults() {
    keywordController.clear();
    results = const [];
    playlistResults = const [];
    selectedPlaylist = null;
    playlistTracks = const [];
    _resetSongPaging();
    _resetPlaylistPaging();
    _resetPlaylistTrackPaging();
    notifyListeners();
  }

  /// 从歌单详情返回歌单列表，并作废在途的分页请求。
  void closePlaylist() {
    selectedPlaylist = null;
    playlistTracks = const [];
    _playlistTrackGeneration++;
    _resetPlaylistTrackPaging();
    notifyListeners();
  }

  Future<void> search() async {
    final keyword = keywordController.text.trim();
    if (keyword.isEmpty || searching) return;

    // 关键词保存到本地
    onlineSearchHistory.add(keyword);

    final searcher = activeSearcher;
    final generation = ++_searchGeneration;
    searching = true;
    if (searchType == OnlineSearchType.song) {
      results = const [];
      _resetSongPaging();
    } else {
      selectedPlaylist = null;
      playlistTracks = const [];
      playlistResults = const [];
      _resetPlaylistPaging();
    }
    notifyListeners();

    try {
      if (searchType == OnlineSearchType.song) {
        final tracks = await searcher.search(keyword, page: 1);
        if (_disposed || generation != _searchGeneration) return;
        searching = false;
        results = tracks;
        songPage = 1;
        songHasMore = tracks.isNotEmpty;
      } else {
        final playlists = await searcher.searchPlaylists(keyword, page: 1);
        if (_disposed || generation != _searchGeneration) return;
        searching = false;
        playlistResults = playlists;
        playlistPage = 1;
        playlistHasMore = playlists.isNotEmpty;
      }
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _searchGeneration) return;
      searching = false;
      notifyListeners();
      onMessage('${searcher.label}：${e is OnlineApiException ? e.message : e}');
    }
  }

  Future<void> loadMoreSongs() async {
    if (songLoadingMore || !songHasMore) return;
    final keyword = keywordController.text.trim();
    if (keyword.isEmpty) return;
    final searcher = activeSearcher;
    final generation = _searchGeneration;

    songLoadingMore = true;
    notifyListeners();
    try {
      final tracks = await searcher.search(keyword, page: songPage + 1);
      // 期间又发起了新搜索的话这次结果作废（新搜索已重置加载标志）。
      if (_disposed || generation != _searchGeneration) return;
      songLoadingMore = false;
      songPage += 1;
      results = [...results, ...tracks];
      songHasMore = tracks.isNotEmpty;
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _searchGeneration) return;
      songLoadingMore = false;
      songHasMore = false;
      notifyListeners();
      onMessage('${searcher.label}：${e is OnlineApiException ? e.message : e}');
    }
  }

  Future<void> loadMorePlaylists() async {
    if (playlistLoadingMore || !playlistHasMore) return;
    final keyword = keywordController.text.trim();
    if (keyword.isEmpty) return;
    final searcher = activeSearcher;
    final generation = _searchGeneration;

    playlistLoadingMore = true;
    notifyListeners();
    try {
      final playlists = await searcher.searchPlaylists(
        keyword,
        page: playlistPage + 1,
      );
      if (_disposed || generation != _searchGeneration) return;
      playlistLoadingMore = false;
      playlistPage += 1;
      playlistResults = [...playlistResults, ...playlists];
      playlistHasMore = playlists.isNotEmpty;
      notifyListeners();
    } catch (e) {
      if (_disposed || generation != _searchGeneration) return;
      playlistLoadingMore = false;
      playlistHasMore = false;
      notifyListeners();
      onMessage('${searcher.label}：${e is OnlineApiException ? e.message : e}');
    }
  }

  Future<void> openPlaylist(OnlinePlaylist playlist) async {
    final searcher = onlineSearchers[playlist.source];
    if (searcher == null) {
      onMessage('未找到对应音源解析器');
      return;
    }

    final generation = ++_playlistTrackGeneration;
    selectedPlaylist = playlist;
    playlistTracks = const [];
    loadingPlaylistTracks = true;
    _resetPlaylistTrackPaging();
    notifyListeners();

    await _loadPlaylistTracksPage(
      searcher: searcher,
      playlist: playlist,
      page: 1,
      generation: generation,
    );
  }

  Future<void> loadMorePlaylistTracks() async {
    if (playlistTrackLoadingMore || !playlistTrackHasMore) return;
    final playlist = selectedPlaylist;
    final searcher = playlist == null ? null : onlineSearchers[playlist.source];
    if (playlist == null || searcher == null) return;

    playlistTrackLoadingMore = true;
    notifyListeners();
    await _loadPlaylistTracksPage(
      searcher: searcher,
      playlist: playlist,
      page: playlistTrackPage + 1,
      generation: _playlistTrackGeneration,
    );
  }

  /// 取歌单的第 [page] 页曲目。第 1 页覆盖列表（换了歌单），后续页追加。
  Future<void> _loadPlaylistTracksPage({
    required OnlineSearcher searcher,
    required OnlinePlaylist playlist,
    required int page,
    required int generation,
  }) async {
    try {
      final tracks = await searcher.getPlaylistTracks(
        playlist.id,
        page: page,
        pageSize: _playlistTrackPageSize,
      );
      if (_disposed || generation != _playlistTrackGeneration) return;
      playlistTracks = page == 1 ? tracks : [...playlistTracks, ...tracks];
      playlistTrackPage = page;
      playlistTrackHasMore = tracks.length >= _playlistTrackPageSize;
      loadingPlaylistTracks = false;
      playlistTrackLoadingMore = false;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      loadingPlaylistTracks = false;
      playlistTrackLoadingMore = false;
      playlistTrackHasMore = false;
      notifyListeners();
      onMessage('加载歌单曲目失败：${e is OnlineApiException ? e.message : e}');
    }
  }

  /// 交集：歌曲实际有的音质 ∩ 接口声明的音质。取不到接口声明就用歌曲自带的。
  List<String> qualitysOf(OnlineTrack track) {
    final declared = apiSources[track.source];
    final own = track.qualitys;
    if (declared == null || declared.isEmpty) return own;
    return own.where(declared.contains).toList();
  }

  String qualityFor(OnlineTrack track) {
    final available = qualitysOf(track);
    if (available.isEmpty) return onlineSettings.quality.value;
    final preferred = onlineSettings.quality.value;
    if (available.contains(preferred)) return preferred;
    return available.first;
  }

  @override
  void dispose() {
    _disposed = true;
    keywordController.dispose();
    super.dispose();
  }
}

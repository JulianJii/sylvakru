// 音源搜索接口、歌单详情缓存 mixin 与音源注册表。

import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/searchers/kg_searcher.dart';
import 'package:sylvakru/online_music/api/searchers/kw_searcher.dart';
import 'package:sylvakru/online_music/api/searchers/mg_searcher.dart';
import 'package:sylvakru/online_music/api/searchers/tx_searcher.dart';
import 'package:sylvakru/online_music/api/searchers/wy_searcher.dart';

/// 一个音源要提供的搜索能力。
abstract class OnlineSearcher {
  String get source;

  String get label;

  int get pageSize;

  Future<List<OnlineTrack>> search(String keyword, {int page});

  Future<List<OnlinePlaylist>> searchPlaylists(String keyword, {int page});

  Future<List<OnlineTrack>> getPlaylistTracks(
    String playlistId, {
    int page,
    int pageSize,
  });
}

/// 歌单详情「一次拉全量再按页切片」的共用实现，kg / tx / wy 三个音源共用。
///
/// 缓存只放内存，进程退出即失效（ponytail: 够用）。
mixin PlaylistDetailCache implements OnlineSearcher {
  final Map<String, List<OnlineTrack>> _detailCache = {};

  @override
  Future<List<OnlineTrack>> getPlaylistTracks(
    String playlistId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    var all = _detailCache[playlistId];
    // 成功才写缓存：失败不缓存，重试还能重新拉。
    all ??= await fetchPlaylistDetail(playlistId);
    _detailCache[playlistId] = all;
    return slicedPage(all, page, pageSize);
  }

  /// 拉取整张歌单的曲目（各音源自己实现）。
  Future<List<OnlineTrack>> fetchPlaylistDetail(String playlistId);
}

final Map<String, OnlineSearcher> onlineSearchers = {
  'kw': KwSearcher(),
  'kg': KgSearcher(),
  'tx': TxSearcher(),
  'wy': WySearcher(),
  'mg': MgSearcher(),
};

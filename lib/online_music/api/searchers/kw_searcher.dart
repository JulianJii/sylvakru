// 酷我音源：接口与解析规则取自 lx-music 的 `musicSdk/kw/musicSearch.js`。

import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_searcher.dart';

/// 酷我。
class KwSearcher implements OnlineSearcher {
  @override
  String get source => 'kw';

  @override
  String get label => '酷我';

  @override
  int get pageSize => 30;

  static final RegExp _qualityPattern = RegExp(
    r'level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)',
  );

  @override
  Future<List<OnlineTrack>> search(String keyword, {int page = 1}) async {
    final query =
        'client=kt'
        '&all=${Uri.encodeComponent(keyword)}'
        '&pn=${page - 1}'
        '&rn=$pageSize'
        '&uid=794762570'
        '&ver=kwplayer_ar_9.2.2.1'
        '&vipver=1'
        '&show_copyright_off=1'
        '&newver=1'
        '&ft=music'
        '&cluster=0'
        '&strategy=2012'
        '&encoding=utf8'
        '&rformat=json'
        '&vermerge=1'
        '&mobi=1'
        '&issubtitle=1';
    final json = await jsonGet(
      Uri.parse('https://search.kuwo.cn/r.s?$query'),
      '酷我搜索',
    );
    return parseAbslist(json['abslist']);
  }

  /// 解析酷我搜索响应的 `abslist`。
  List<OnlineTrack> parseAbslist(Object? abslist) {
    final result = <OnlineTrack>[];
    for (final item in (abslist as List?) ?? const []) {
      final info = asMap(item);
      final musicRid = '${info['MUSICRID'] ?? ''}';
      final nMinfo = info['N_MINFO'];
      // 没有 N_MINFO 的条目不可播（搜索结果里会混着非歌曲项）。
      if (musicRid.isEmpty || nMinfo is! String || nMinfo.isEmpty) continue;
      final types = _parseQualitys(nMinfo);
      if (types.isEmpty) continue;
      result.add(
        OnlineTrack(
          source: source,
          songmid: musicRid.replaceFirst('MUSIC_', ''),
          name: decodeName('${info['SONGNAME'] ?? ''}'),
          singer: decodeName('${info['ARTIST'] ?? ''}'),
          albumName: decodeName('${info['ALBUM'] ?? ''}'),
          albumId: decodeName('${info['ALBUMID'] ?? ''}'),
          interval: formatPlayTime(int.tryParse('${info['DURATION']}')),
          types: types,
        ),
      );
    }
    return result;
  }

  /// `N_MINFO` 是 `level:x,bitrate:n,format:y,size:z` 的分号列表，
  /// bitrate 4000/2000/320/128 分别对应 flac24bit/flac/320k/128k。
  static List<Map<String, String>> _parseQualitys(String nMinfo) {
    final byType = <String, Map<String, String>>{};
    for (final chunk in nMinfo.split(';')) {
      final match = _qualityPattern.firstMatch(chunk);
      if (match == null) continue;
      final type = switch (match.group(2)) {
        '4000' => 'flac24bit',
        '2000' => 'flac',
        '320' => '320k',
        '128' => '128k',
        _ => null,
      };
      if (type == null) continue;
      byType[type] = {'type': type, 'size': (match.group(4) ?? '').toUpperCase()};
    }
    return qualityOrder.where(byType.containsKey).map((t) => byType[t]!).toList();
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(String keyword, {int page = 1}) async {
    final query =
        'client=kt'
        '&all=${Uri.encodeComponent(keyword)}'
        '&pn=${page - 1}'
        '&rn=$pageSize'
        '&uid=794762570'
        '&ver=kwplayer_ar_9.2.2.1'
        '&vipver=1'
        '&show_copyright_off=1'
        '&newver=1'
        '&ft=playlist'
        '&cluster=0'
        '&strategy=2012'
        '&encoding=utf8'
        '&rformat=json'
        '&vermerge=1'
        '&mobi=1';
    final json = await jsonGet(
      Uri.parse('https://search.kuwo.cn/r.s?$query'),
      '酷我歌单搜索',
    );
    return parsePlaylistAbslist(json['abslist']);
  }

  List<OnlinePlaylist> parsePlaylistAbslist(Object? abslist) {
    final result = <OnlinePlaylist>[];
    for (final item in (abslist as List?) ?? const []) {
      final info = asMap(item);
      final id = '${info['playlistid'] ?? info['DC_TARGETID'] ?? ''}';
      if (id.isEmpty) continue;
      final pic = '${info['pic'] ?? info['hts_pic'] ?? ''}';
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${info['name'] ?? ''}'),
          creator: decodeName('${info['nickname'] ?? ''}'),
          pic: pic,
          songCount: int.tryParse('${info['songnum'] ?? 0}') ?? 0,
          playCount: int.tryParse('${info['playcnt'] ?? 0}') ?? 0,
          intro: decodeName('${info['intro'] ?? ''}'),
        ),
      );
    }
    return result;
  }

  @override
  Future<List<OnlineTrack>> getPlaylistTracks(
    String playlistId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final json = await jsonGet(
      Uri.parse(
        'https://m.kuwo.cn/newh5app/wapi/api/www/playlist/playListInfo'
        '?pid=$playlistId&pn=$page&rn=$pageSize',
      ),
      '酷我歌单详情',
    );
    final data = asMap(json['data']);
    final musicList = (data['musicList'] as List?) ?? const [];
    final result = <OnlineTrack>[];
    for (final item in musicList) {
      final info = asMap(item);
      final musicrid = '${info['musicrid'] ?? ''}';
      final songmid = musicrid.isNotEmpty
          ? musicrid.replaceFirst('MUSIC_', '')
          : '${info['rid'] ?? ''}';
      if (songmid.isEmpty) continue;
      final duration = int.tryParse('${info['duration'] ?? 0}') ?? 0;
      final pic = '${info['pic'] ?? info['albumpic'] ?? ''}';

      result.add(
        OnlineTrack(
          source: source,
          songmid: songmid,
          name: decodeName('${info['name'] ?? ''}'),
          singer: decodeName('${info['artist'] ?? ''}'),
          albumName: decodeName('${info['album'] ?? ''}'),
          albumId: '${info['albumid'] ?? ''}',
          interval: formatPlayTime(duration),
          img: pic.isEmpty ? null : pic,
          types: const [
            {'type': '128k', 'size': ''},
            {'type': '320k', 'size': ''},
            {'type': 'flac', 'size': ''},
          ],
        ),
      );
    }
    return result;
  }
}

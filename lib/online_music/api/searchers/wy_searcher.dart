// 网易云音乐音源：接口与加密规则取自 lx-music 的 `musicSdk/wy/musicSearch.js`
// 与 `songList.js`。

import 'package:sylvakru/online_music/api/online_crypto.dart';
import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_searcher.dart';

/// 网易。搜索/歌单搜索走 eapi，歌单详情走 linuxapi。
/// 请求体要加密，响应是明文 JSON（lx 请求层同样不解密）。
class WySearcher with PlaylistDetailCache implements OnlineSearcher {
  @override
  String get source => 'wy';

  @override
  String get label => '网易';

  @override
  int get pageSize => 30;

  static const String _wyUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/60.0.3112.90 Safari/537.36';

  /// eapi 请求：POST form，只有一个加密后的 `params` 字段。
  Future<Map<String, dynamic>> _eapi(String apiUrl, Object data) async {
    final response = await httpPost(
      Uri.parse('http://interface.music.163.com/eapi/batch'),
      {'params': wyEapiParams(apiUrl, data)},
      headers: {'User-Agent': _wyUserAgent, 'origin': 'https://music.163.com'},
    );
    return asJsonObject(decodeBody(response.bodyBytes), '网易接口');
  }

  @override
  Future<List<OnlineTrack>> search(String keyword, {int page = 1}) async {
    final json = await _eapi('/api/search/song/list/page', {
      'keyword': keyword,
      'needCorrect': '1',
      'channel': 'typing',
      'offset': pageSize * (page - 1),
      'scene': 'normal',
      'total': page == 1,
      'limit': pageSize,
    });
    if (json['code'] != 200) {
      throw OnlineApiException('网易搜索失败（code=${json['code']}）');
    }
    final result = <OnlineTrack>[];
    for (final raw in (asMap(json['data'])['resources'] as List?) ?? const []) {
      final item = asMap(asMap(asMap(raw)['baseInfo'])['simpleSongData']);
      if (item.isEmpty) continue;
      final track = _parseTrack(item, asMap(item['privilege']));
      if (track != null) result.add(track);
    }
    return result;
  }

  /// lx 原实现是 switch 贯穿 fallthrough：高音质命中时低音质全都要，
  /// hires 另看 maxBrLevel。这里按 qualityOrder 顺序等价重建。
  OnlineTrack? _parseTrack(Map<String, dynamic> item, Map<String, dynamic> privilege) {
    final maxbr = asInt(privilege['maxbr']);
    final hires = '${privilege['maxBrLevel'] ?? ''}' == 'hires';
    String? sizeOf(String field) {
      final bytes = asInt(asMap(item[field])['size']);
      return bytes > 0 ? formatSize(bytes) : null;
    }

    final types = <String, Map<String, String>>{};
    void addType(String label, String field) {
      final size = sizeOf(field);
      if (size != null) types[label] = {'type': label, 'size': size};
    }

    if (hires) addType('flac24bit', 'hr');
    if (maxbr >= 999000) addType('flac', 'sq');
    if (maxbr >= 320000) addType('320k', 'h');
    if (maxbr >= 128000) addType('128k', 'l');
    if (types.isEmpty) return null;
    final al = asMap(item['al']);
    final pic = '${al['picUrl'] ?? ''}';
    return OnlineTrack(
      source: source,
      songmid: '${item['id'] ?? ''}',
      name: decodeName('${item['name'] ?? ''}'),
      singer: formatSingerName(item['ar']),
      albumName: decodeName('${al['name'] ?? ''}'),
      albumId: '${al['id'] ?? ''}',
      interval: formatPlayTime(asInt(item['dt']) ~/ 1000),
      img: pic.isEmpty ? null : pic,
      types: [
        for (final quality in qualityOrder)
          if (types[quality] != null) types[quality]!,
      ],
    );
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(
    String keyword, {
    int page = 1,
  }) async {
    final json = await _eapi('/api/cloudsearch/pc', {
      's': keyword,
      'type': 1000, // 1000 = 歌单
      'limit': 20,
      'total': page == 1,
      'offset': 20 * (page - 1),
    });
    if (json['code'] != 200) {
      throw OnlineApiException('网易歌单搜索失败（code=${json['code']}）');
    }
    final result = <OnlinePlaylist>[];
    for (final raw in (asMap(json['result'])['playlists'] as List?) ?? const []) {
      final item = asMap(raw);
      final id = '${item['id'] ?? ''}';
      if (id.isEmpty) continue;
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${item['name'] ?? ''}'),
          creator: decodeName(asMap(item['creator'])['nickname'] ?? ''),
          pic: '${item['coverImgUrl'] ?? ''}',
          songCount: int.tryParse('${item['trackCount'] ?? 0}') ?? 0,
          playCount: int.tryParse('${item['playCount'] ?? 0}') ?? 0,
          intro: decodeName('${item['description'] ?? ''}'),
        ),
      );
    }
    return result;
  }

  /// 歌单详情走 linuxapi 转发（lx `wy/songList.js`）。
  /// ponytail: trackIds 与 privileges 数量不一致（超长歌单详情被截断）时，
  /// lx 会退 weapi 批量详情（要 RSA no-padding），这里直接报错，真遇到再加。
  @override
  Future<List<OnlineTrack>> fetchPlaylistDetail(String playlistId) async {
    final response = await httpPost(
      Uri.parse('https://music.163.com/api/linux/forward'),
      {
        'eparams': wyLinuxParams({
          'method': 'POST',
          'url': 'https://music.163.com/api/v3/playlist/detail',
          'params': {'id': playlistId, 'n': 100000, 's': 8},
        }),
      },
      headers: {'User-Agent': _wyUserAgent, 'Cookie': 'MUSIC_U='},
    );
    final json = asJsonObject(decodeBody(response.bodyBytes), '网易歌单详情');
    if (json['code'] != 200) {
      throw OnlineApiException('网易歌单详情失败（code=${json['code']}）');
    }
    final playlist = asMap(json['playlist']);
    final trackIds = (playlist['trackIds'] as List?) ?? const [];
    final privileges = (json['privileges'] as List?) ?? const [];
    if (trackIds.isEmpty || trackIds.length != privileges.length) {
      throw OnlineApiException('歌单详情不完整（${trackIds.length}/${privileges.length}），暂不支持');
    }
    final tracks = (playlist['tracks'] as List?) ?? const [];
    final result = <OnlineTrack>[];
    for (var i = 0; i < privileges.length; i++) {
      final item = asMap(i < tracks.length ? tracks[i] : null);
      if (item.isEmpty) continue;
      // pc 字段是云盘上传的修正信息，lx 同口径优先用它。
      final pc = asMap(item['pc']);
      final al = asMap(item['al']);
      final track = _parseTrack(
        {
          ...item,
          if (pc.isNotEmpty) ...{
            'name': '${pc['sn'] ?? item['name']}',
            'ar': pc['ar'] ?? item['ar'],
            'al': {...al, if (pc['alb'] != null) 'name': pc['alb']},
          },
        },
        asMap(privileges[i]),
      );
      if (track != null) result.add(track);
    }
    return result;
  }
}

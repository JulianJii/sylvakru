// 酷狗音源：接口与解析规则取自 lx-music 的 `musicSdk/kg/musicSearch.js`
// 与 `songList.js`。

import 'dart:convert';

import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_searcher.dart';

/// 酷狗。搜索无加密；歌单详情抓页面 HTML 拿 hash 列表后
/// 走 gateway 批量接口换详情。
class KgSearcher with PlaylistDetailCache implements OnlineSearcher {
  @override
  String get source => 'kg';

  @override
  String get label => '酷狗';

  @override
  int get pageSize => 30;

  @override
  Future<List<OnlineTrack>> search(String keyword, {int page = 1}) async {
    final json = await jsonGet(
      Uri.parse(
        'http://songsearch.kugou.com/song_search_v2?platform=AndroidFilter'
        '&iscorrection=1&keyword=${Uri.encodeComponent(keyword)}'
        '&hifiquality=0&pagesize=$pageSize&PrivilegeFilter=0&page=$page',
      ),
      '酷狗搜索',
    );
    if ('${json['error_code']}' != '0') {
      throw OnlineApiException('酷狗搜索失败（error_code=${json['error_code']}）');
    }
    return _parseSongList((asMap(json['data'])['lists'] as List?) ?? const []);
  }

  /// `lists` 条目：各音质的 FileSize/FileHash，`Grp` 是同曲多版本子项，
  /// 按 Audioid+FileHash 去重。
  List<OnlineTrack> _parseSongList(List list) {
    final result = <OnlineTrack>[];
    final seen = <String>{};
    void add(Map<String, dynamic> item) {
      final audioId = '${item['Audioid'] ?? ''}';
      final hash = '${item['FileHash'] ?? ''}';
      if (audioId.isEmpty || hash.isEmpty || !seen.add('$audioId$hash')) return;
      final types = qualitysOf(item, const {
        '128k': ('FileSize', 'FileHash'),
        '320k': ('HQFileSize', 'HQFileHash'),
        'flac': ('SQFileSize', 'SQFileHash'),
        'flac24bit': ('ResFileSize', 'ResFileHash'),
      });
      if (types.isEmpty) return;
      final suffix = '${item['Suffix'] ?? ''}';
      result.add(
        OnlineTrack(
          source: source,
          songmid: audioId,
          name: decodeName(
            '${item['OriSongName'] ?? ''}${suffix.isEmpty ? '' : ' $suffix'}',
          ),
          singer: formatSingerName(item['Singers']),
          albumName: decodeName('${item['AlbumName'] ?? ''}'),
          albumId: '${item['AlbumID'] ?? ''}',
          interval: formatPlayTime(int.tryParse('${item['Duration']}')),
          types: types,
          extra: {'hash': hash, 'albumAudioId': '${item['MixSongID'] ?? ''}'},
        ),
      );
    }

    for (final raw in list) {
      final item = asMap(raw);
      add(item);
      for (final child in (item['Grp'] as List?) ?? const []) {
        add(asMap(child));
      }
    }
    return result;
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(
    String keyword, {
    int page = 1,
  }) async {
    final json = await jsonGet(
      Uri.parse(
        'http://msearchretry.kugou.com/api/v3/search/special'
        '?keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=20'
        '&showtype=10&filter=0&version=7910&sver=2',
      ),
      '酷狗歌单搜索',
    );
    if ('${json['errcode']}' != '0') {
      throw OnlineApiException('酷狗歌单搜索失败（errcode=${json['errcode']}）');
    }
    final result = <OnlinePlaylist>[];
    for (final raw in (asMap(json['data'])['info'] as List?) ?? const []) {
      final item = asMap(raw);
      final id = '${item['specialid'] ?? ''}';
      if (id.isEmpty) continue;
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${item['specialname'] ?? ''}'),
          creator: decodeName('${item['nickname'] ?? ''}'),
          pic: '${item['imgurl'] ?? ''}',
          songCount: int.tryParse('${item['songcount'] ?? 0}') ?? 0,
          playCount: int.tryParse('${item['playcount'] ?? 0}') ?? 0,
          intro: decodeName('${item['intro'] ?? ''}'),
        ),
      );
    }
    return result;
  }

  /// specialid 详情：`…single/{id}-5-9999.html` 页面里的 `global.data = […]`
  /// 只有 hash，拿去按 100/批换完整详情（lx `getListDetailBySpecialId` +
  /// `getMusicInfos`）。我们的歌单 id 都来自自家搜索，只处理这一个分支。
  @override
  Future<List<OnlineTrack>> fetchPlaylistDetail(String specialId) async {
    final response = await httpGet(
      Uri.parse(
        'http://www2.kugou.kugou.com/yueku/v9/special/single/'
        '$specialId-5-9999.html',
      ),
    );
    final match = RegExp(
      r'global\.data = (\[.+\]);',
    ).firstMatch(decodeBody(response.bodyBytes));
    if (match == null) throw OnlineApiException('酷狗歌单详情解析失败');
    final hashes = <String>[];
    final seen = <String>{};
    for (final raw in jsonDecode(match.group(1)!) as List) {
      final hash = '${asMap(raw)['hash'] ?? ''}';
      if (hash.isNotEmpty && seen.add(hash)) hashes.add(hash);
    }

    final result = <OnlineTrack>[];
    final ids = <String>{};
    for (var start = 0; start < hashes.length; start += 100) {
      final json = await httpPostJson(
        Uri.parse('http://gateway.kugou.com/v2/album_audio/audio'),
        {
          'area_code': '1',
          'show_privilege': 1,
          'show_album_info': '1',
          'is_publish': '',
          'appid': 1005,
          'clientver': 11451,
          'mid': '1',
          'dfid': '-',
          'clienttime': DateTime.now().millisecondsSinceEpoch,
          'key': 'OIlwieks28dk2k092lksi2UIkp',
          'fields':
              'album_info,author_name,audio_info,ori_audio_name,base,songname',
          'data': hashes.sublist(
            start,
            (start + 100).clamp(0, hashes.length),
          ),
        },
        '酷狗歌单详情',
        headers: {
          'KG-THash': '13a3164',
          'KG-RC': '1',
          'KG-Fake': '0',
          'KG-RF': '00869891',
          'User-Agent':
              'Android712-AndroidPhone-11451-376-0-FeeCacheUpdate-wifi',
          'x-router': 'kmr.service.kugou.com',
        },
      );
      // 响应 data 是 [[item], [item]…] 的二维数组，取每组第一个。
      for (final group in (json['data'] as List?) ?? const []) {
        if (group is! List || group.isEmpty) continue;
        final item = asMap(group.first);
        final audio = asMap(item['audio_info']);
        final audioId = '${audio['audio_id'] ?? ''}';
        if (audioId.isEmpty || !ids.add(audioId)) continue;
        final types = qualitysOf(audio, const {
          '128k': ('filesize', 'hash'),
          '320k': ('filesize_320', 'hash_320'),
          'flac': ('filesize_flac', 'hash_flac'),
          'flac24bit': ('filesize_high', 'hash_high'),
        });
        if (types.isEmpty) continue;
        result.add(
          OnlineTrack(
            source: source,
            songmid: audioId,
            name: decodeName('${item['songname'] ?? ''}'),
            singer: decodeName('${item['author_name'] ?? ''}'),
            albumName: decodeName(asMap(item['album_info'])['album_name'] ?? ''),
            albumId: '${asMap(item['album_info'])['album_id'] ?? ''}',
            interval: formatPlayTime(asInt(audio['timelength']) ~/ 1000),
            types: types,
            extra: {
              'hash': '${audio['hash'] ?? ''}',
              'albumAudioId': '${audio['audio_group_id'] ?? ''}',
            },
          ),
        );
      }
    }
    return result;
  }
}

// QQ 音乐音源：接口与签名规则取自 lx-music 的 `musicSdk/tx/musicSearch.js`
// 与 `songList.js`。

import 'dart:convert';
import 'dart:math';

import 'package:sylvakru/online_music/api/online_crypto.dart';
import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_searcher.dart';

/// QQ 音乐。搜索走 musics.fcg + zzcSign；歌单搜索/详情是普通
/// GET/POST，不需要签名。
class TxSearcher with PlaylistDetailCache implements OnlineSearcher {
  @override
  String get source => 'tx';

  @override
  String get label => 'QQ音乐';

  @override
  int get pageSize => 50;

  /// lx `comm` 固定字段（PC 客户端伪装）。
  static const Map<String, Object> _comm = {
    '_channelid': '0',
    '_os_version': '6.2.9200-2',
    'ct': '19',
    'cv': '2151',
    'guid': '1F70E520B2EAA7D25E11760783C53CA9',
    'patch': '118',
    'psrf_access_token_expiresAt': 0,
    'psrf_qqaccess_token': '',
    'psrf_qqopenid': '',
    'psrf_qqunionid': '',
    'tmeAppID': 'qqmusic',
    'tmeLoginType': 0,
    'uin': '0',
    'wid': '7223299733393904640',
  };

  /// lx `getSearchId`：32 位大写 hex + 5 位补零随机数。
  String _searchId() {
    final guid = [
      for (var i = 0; i < 32; i++) Random().nextInt(16).toRadixString(16),
    ].join().toUpperCase();
    return '$guid${Random().nextInt(100000).toString().padLeft(5, '0')}';
  }

  /// lx `signRequest`：zzcSign 放 URL query，POST JSON，失败重试最多 5 次。
  Future<Map<String, dynamic>> _signRequest(
    String module,
    Map<String, Object> param,
  ) async {
    Object? lastCode;
    for (var attempt = 0; attempt < 5; attempt++) {
      final data = <String, Object>{
        'comm': _comm,
        module: {'module': module, 'method': 'DoSearchForQQMusicDesktop', 'param': param},
      };
      final json = await httpPostJson(
        Uri.parse(
          'https://u.y.qq.com/cgi-bin/musics.fcg'
          '?sign=${txZzcSign(jsonEncode(data))}',
        ),
        data,
        'QQ音乐搜索',
        headers: {'User-Agent': 'QQMusic 14090508(android 12)'},
      );
      lastCode = json['code'];
      final entry = json[module] ?? json['req'];
      if (json['code'] == 0 && entry is Map && asMap(entry)['code'] == 0) {
        return asMap(asMap(entry)['data']);
      }
    }
    throw OnlineApiException('QQ音乐搜索失败（code=$lastCode）');
  }

  @override
  Future<List<OnlineTrack>> search(String keyword, {int page = 1}) async {
    final data = await _signRequest('music.search.SearchCgiService', {
      'grp': 1,
      'num_per_page': pageSize,
      'page_num': page,
      'query': keyword,
      'remoteplace': 'txt.newclient.top',
      'search_type': 0,
      'searchid': _searchId(),
    });
    final song = asMap(asMap(asMap(data)['body'])['song']);
    return _parseSongList((song['list'] as List?) ?? const []);
  }

  /// 条目质量在 `file` 里：size_128mp3 / size_320mp3 / size_flac / size_hires。
  List<OnlineTrack> _parseSongList(List list) {
    final result = <OnlineTrack>[];
    for (final raw in list) {
      final item = asMap(raw);
      final file = asMap(item['file']);
      final mediaMid = '${file['media_mid'] ?? ''}';
      if (mediaMid.isEmpty) continue;
      final types = <String, Map<String, String>>{
        for (final entry in {
          '128k': 'size_128mp3',
          '320k': 'size_320mp3',
          'flac': 'size_flac',
          'flac24bit': 'size_hires',
        }.entries)
          if (asInt(file[entry.value]) != 0)
            entry.key: {'type': entry.key, 'size': formatSize(asInt(file[entry.value]))},
      };
      if (types.isEmpty) continue;
      final album = asMap(item['album']);
      final albumMid = '${album['mid'] ?? ''}';
      final singers = item['singer'];
      // 无专辑（或专辑名是占位"空"）时退歌手图，口径同 lx。
      final String img;
      if (albumMid.isEmpty || albumMid == '空') {
        final first = singers is List && singers.isNotEmpty
            ? asMap(singers.first)['mid']
            : null;
        img = first == null
            ? ''
            : 'https://y.gtimg.cn/music/photo_new/T001R500x500M000$first.jpg';
      } else {
        img = 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg';
      }
      result.add(
        OnlineTrack(
          source: source,
          songmid: '${item['mid'] ?? ''}',
          name: decodeName('${item['title'] ?? ''}'),
          singer: formatSingerName(singers),
          albumName: decodeName('${album['name'] ?? ''}'),
          albumId: albumMid,
          interval: formatPlayTime(int.tryParse('${item['interval']}')),
          img: img.isEmpty ? null : img,
          types: [
            for (final quality in qualityOrder)
              if (types[quality] != null) types[quality]!,
          ],
          extra: {
            'songId': '${item['id'] ?? ''}',
            'strMediaMid': mediaMid,
            'albumMid': albumMid,
          },
        ),
      );
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
        'http://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist'
        '?page_no=${page - 1}&num_per_page=20&format=json'
        '&query=${Uri.encodeComponent(keyword)}'
        '&remoteplace=txt.yqq.playlist&inCharset=utf8&outCharset=utf-8',
      ),
      'QQ音乐歌单搜索',
      headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
        'Referer': 'http://y.qq.com/portal/search.html',
      },
    );
    if (json['code'] != 0) {
      throw OnlineApiException('QQ音乐歌单搜索失败（code=${json['code']}）');
    }
    final result = <OnlinePlaylist>[];
    for (final raw in (asMap(json['data'])['list'] as List?) ?? const []) {
      final item = asMap(raw);
      final id = '${item['dissid'] ?? ''}';
      if (id.isEmpty) continue;
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${item['dissname'] ?? ''}'),
          creator: decodeName(asMap(item['creator'])['name'] ?? ''),
          pic: '${item['imgurl'] ?? ''}',
          songCount: int.tryParse('${item['song_count'] ?? 0}') ?? 0,
          playCount: int.tryParse('${item['listennum'] ?? 0}') ?? 0,
          intro: decodeName('${item['introduction'] ?? ''}').replaceAll('<br>', '\n'),
        ),
      );
    }
    return result;
  }

  /// 歌单详情：fcg_ucc 接口优先，code 不对退 musicu.fcg（lx `tx/songList.js`
  /// 的 getListDetail / getListDetail2）。两个接口都一次拉全量。
  @override
  Future<List<OnlineTrack>> fetchPlaylistDetail(String dissId) async {
    final primary = await jsonGet(
      Uri.parse(
        'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg'
        '?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=$dissId'
        '&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8'
        '&notice=0&platform=yqq.json&needNewCode=0',
      ),
      'QQ音乐歌单详情',
      headers: {
        'Origin': 'https://y.qq.com',
        'Referer': 'https://y.qq.com/n/yqq/playsquare/$dissId.html',
      },
    );
    final cdlist = (primary['cdlist'] as List?) ?? const [];
    if (primary['code'] == 0 && primary['subcode'] == 0 && cdlist.isNotEmpty) {
      return _parseSongList((asMap(cdlist.first)['songlist'] as List?) ?? const []);
    }

    final fallback = await httpPostJson(
      Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
      {
        'comm': {
          'cv': 4747474,
          'ct': 24,
          'format': 'json',
          'inCharset': 'utf-8',
          'outCharset': 'utf-8',
          'platform': 'yqq.json',
          'needNewCode': 1,
          'uin': 0,
        },
        'req_1': {
          'module': 'music.srfDissInfo.aiDissInfo',
          'method': 'uniform_get_Dissinfo',
          'param': {
            'disstid': int.tryParse(dissId) ?? 0,
            'userinfo': 1,
            'tag': 1,
            'orderlist': 1,
            'song_begin': 0,
            'song_num': 100000,
            'onlysonglist': 0,
            'enc_host_uin': '',
          },
        },
      },
      'QQ音乐歌单详情',
      headers: {
        'Origin': 'https://y.qq.com',
        'Referer': 'https://y.qq.com/n/yqq/playsquare/$dissId.html',
      },
    );
    final req1 = asMap(fallback['req_1']);
    if (fallback['code'] != 0 || req1['code'] != 0) {
      throw OnlineApiException('QQ音乐歌单详情失败（code=${req1['code'] ?? fallback['code']}）');
    }
    return _parseSongList((asMap(req1['data'])['songlist'] as List?) ?? const []);
  }
}

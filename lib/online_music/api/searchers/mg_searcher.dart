// 咪咕音源：接口、签名与解析规则取自 lx-music 的 `musicSdk/mg/musicSearch.js`。

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_searcher.dart';

/// 咪咕。
class MgSearcher implements OnlineSearcher {
  @override
  String get source => 'mg';

  @override
  String get label => '咪咕';

  @override
  int get pageSize => 20;

  static const String deviceId = '963B7AA0D21511ED807EE5846EC87D20';
  static const String _signatureMd5 = '6cdc72a439cef99a3418d2a78aa28c73';
  static const String _signatureTail = 'yyapp2d16148780a1dcc7408e06336b98cfd50';

  /// 服务端要求的签名：`md5(关键词 + 常量 + 常量 + deviceId + 毫秒时间戳)`。
  static String buildSign(String keyword, String timestamp) => md5
      .convert(
        utf8.encode('$keyword$_signatureMd5$_signatureTail$deviceId$timestamp'),
      )
      .toString();

  @override
  Future<List<OnlineTrack>> search(String keyword, {int page = 1}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final query =
        'isCorrect=0'
        '&isCopyright=1'
        '&searchSwitch=%7B%22song%22%3A1%2C%22album%22%3A0%2C%22singer%22%3A0'
        '%2C%22tagSong%22%3A1%2C%22mvSong%22%3A0%2C%22bestShow%22%3A1'
        '%2C%22songlist%22%3A0%2C%22lyricSong%22%3A0%7D'
        '&pageSize=$pageSize'
        '&text=${Uri.encodeComponent(keyword)}'
        '&pageNo=$page'
        '&sort=0'
        '&sid=USS';
    final json = await jsonGet(
      Uri.parse('https://jadeite.migu.cn/music_search/v3/search/searchAll?$query'),
      '咪咕搜索',
      headers: {
        'uiVersion': 'A_music_3.6.1',
        'deviceId': deviceId,
        'timestamp': timestamp,
        'sign': buildSign(keyword, timestamp),
        'channel': '0146921',
        'User-Agent': mgUserAgent,
      },
    );
    if (json['code'] != '000000') {
      throw OnlineApiException('咪咕搜索失败（code=${json['code']}）');
    }

    return parseResultList(asMap(json['songResultData'])['resultList']);
  }

  /// 解析咪咕搜索响应的 `songResultData.resultList`（二维数组）。
  List<OnlineTrack> parseResultList(Object? resultList) {
    final result = <OnlineTrack>[];
    final seen = <String>{};
    for (final group in (resultList as List?) ?? const []) {
      if (group is! List) continue;
      for (final item in group) {
        final data = asMap(item);
        final copyrightId = '${data['copyrightId'] ?? ''}';
        final songId = '${data['songId'] ?? ''}';
        if (copyrightId.isEmpty ||
            songId.isEmpty ||
            !seen.add(copyrightId)) {
          continue;
        }
        final types = _parseQualitys(data['audioFormats']);
        if (types.isEmpty) continue;

        var img = '${data['img3'] ?? data['img2'] ?? data['img1'] ?? ''}';
        if (img.isNotEmpty && !img.startsWith('http')) {
          img = 'http://d.musicapp.migu.cn$img';
        }

        result.add(
          OnlineTrack(
            source: source,
            songmid: songId,
            name: decodeName('${data['name'] ?? ''}'),
            singer: formatSingerName(data['singerList']),
            albumName: decodeName('${data['album'] ?? ''}'),
            albumId: '${data['albumId'] ?? ''}',
            interval: formatPlayTime(int.tryParse('${data['duration']}')),
            img: img.isEmpty ? null : img,
            types: types,
            extra: {
              'copyrightId': copyrightId,
              if (data['lrcUrl'] != null) 'lrcUrl': data['lrcUrl'],
              if (data['mrcurl'] != null) 'mrcUrl': data['mrcurl'],
              if (data['trcUrl'] != null) 'trcUrl': data['trcUrl'],
            },
          ),
        );
      }
    }
    return result;
  }

  static List<Map<String, String>> _parseQualitys(Object? formats) {
    final byType = <String, Map<String, String>>{};
    for (final raw in (formats as List?) ?? const []) {
      final item = asMap(raw);
      final type = switch ('${item['formatType']}') {
        'PQ' => '128k',
        'HQ' => '320k',
        'SQ' => 'flac',
        'ZQ24' => 'flac24bit',
        _ => null,
      };
      if (type == null) continue;
      byType[type] = {
        'type': type,
        'size': formatSize(int.tryParse('${item['asize'] ?? item['isize']}')),
      };
    }
    return qualityOrder.where(byType.containsKey).map((t) => byType[t]!).toList();
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(String keyword, {int page = 1}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final query =
        'isCorrect=0'
        '&isCopyright=1'
        '&searchSwitch=%7B%22song%22%3A0%2C%22album%22%3A0%2C%22singer%22%3A0'
        '%2C%22tagSong%22%3A0%2C%22mvSong%22%3A0%2C%22bestShow%22%3A0'
        '%2C%22songlist%22%3A1%2C%22lyricSong%22%3A0%7D'
        '&pageSize=$pageSize'
        '&text=${Uri.encodeComponent(keyword)}'
        '&pageNo=$page'
        '&sort=0'
        '&sid=USS';
    final json = await jsonGet(
      Uri.parse('https://jadeite.migu.cn/music_search/v3/search/searchAll?$query'),
      '咪咕歌单搜索',
      headers: {
        'uiVersion': 'A_music_3.6.1',
        'deviceId': deviceId,
        'timestamp': timestamp,
        'sign': buildSign(keyword, timestamp),
        'channel': '0146921',
        'User-Agent': mgUserAgent,
      },
    );
    if (json['code'] != '000000') {
      throw OnlineApiException('咪咕歌单搜索失败（code=${json['code']}）');
    }
    final sld = asMap(json['songListResultData']);
    final list = (sld['result'] as List?) ?? const [];
    final result = <OnlinePlaylist>[];
    for (final item in list) {
      final data = asMap(item);
      final id = '${data['id'] ?? data['musicListId'] ?? ''}';
      if (id.isEmpty) continue;
      var img = '${data['img'] ?? data['musicListPic'] ?? ''}';
      if (img.isNotEmpty && !img.startsWith('http')) {
        img = 'http://d.musicapp.migu.cn$img';
      }
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${data['name'] ?? ''}'),
          creator: decodeName('${data['userName'] ?? ''}'),
          pic: img,
          songCount: int.tryParse('${data['musicNum'] ?? 0}') ?? 0,
          playCount: int.tryParse('${data['playNum'] ?? 0}') ?? 0,
          intro: decodeName('${data['summary'] ?? ''}'),
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
        'https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0'
        '?playlistId=$playlistId&pageNo=$page&pageSize=$pageSize',
      ),
      '咪咕歌单详情',
      headers: {
        'User-Agent': mgUserAgent,
      },
    );
    final data = asMap(json['data']);
    final songList = (data['songList'] as List?) ?? const [];
    final result = <OnlineTrack>[];
    for (final item in songList) {
      final track = asMap(item);
      final copyrightId = '${track['copyrightId'] ?? ''}';
      final songId = '${track['songId'] ?? ''}';
      if (copyrightId.isEmpty || songId.isEmpty) continue;
      final types = _parseQualitys(track['audioFormats']);
      if (types.isEmpty) continue;

      var img = '${track['img3'] ?? track['img2'] ?? track['img1'] ?? ''}';
      if (img.isNotEmpty && !img.startsWith('http')) {
        img = 'http://d.musicapp.migu.cn$img';
      }

      result.add(
        OnlineTrack(
          source: source,
          songmid: songId,
          name: decodeName('${track['songName'] ?? ''}'),
          singer: formatSingerName(track['singerList']),
          albumName: decodeName('${track['album'] ?? ''}'),
          albumId: '${track['albumId'] ?? ''}',
          interval: formatPlayTime(int.tryParse('${track['duration']}')),
          img: img.isEmpty ? null : img,
          types: types,
          extra: {
            'copyrightId': copyrightId,
            if (track['lrcUrl'] != null) 'lrcUrl': track['lrcUrl'],
            if (track['mrcurl'] != null) 'mrcUrl': track['mrcurl'],
            if (track['trcUrl'] != null) 'trcUrl': track['trcUrl'],
          },
        ),
      );
    }
    return result;
  }
}

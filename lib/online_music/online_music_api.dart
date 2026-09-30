// 在线音乐：搜索器 + 本地设置 + 播放直链解析。
//
// 直链解析不再复刻某个具体接口，而是直接跑 lx-music 的「自定义源」脚本：
// Dart 复刻宿主注入的 `window.lx`，用 QuickJS 原样执行用户 JS（见 lx_js/）。
// 脚本怎么取链是脚本自己的事（聚合接口、303 二次校验……），这里只做四件事：
//   1. 等脚本 `lx.send('inited')`，拿到它声明的音源与音质
//   2. 把歌曲对象（lx 旧格式）交给脚本的 request 事件
//   3. 校验脚本返回的直链是 http(s) 且长度合规
//   4. 封面按 lx-music 的 `getPic` 口径取：脚本的 `pic` action 优先，
//      再退到音源自己的接口（酷我 artistpicserver / 咪咕 resourceinfo.do）
//
// 自定义源脚本只注册 request 事件、**不提供搜索**，所以搜索仍由本文件的
// Searcher（kw/kg/tx/wy/mg，与 lx-music 启用的源一致）按 lx-music 内置
// 实现的接口与解析规则自己实现。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:charset/charset.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:http/http.dart' as http;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_bridge.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';

/// 接口地址默认留空：必须由用户在「接口设置」里手动填写自己的洛雪音乐接口，
/// 不再内置任何默认地址。

/// lx-music 对**所有**请求都带这个 UA，酷我/咪咕的接口都依赖它。
const String _lxUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/69.0.3497.100 Safari/537.36';

const String _mgUserAgent =
    'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) '
    'AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30';

/// 与 lx-music 的默认请求超时保持一致。聚合接口走 Cloudflare，
/// 10s 实测偶发超时，15s 更稳。
const Duration _requestTimeout = Duration(seconds: 15);

/// 音质由低到高的惯例顺序，用于给 UI 排序与挑选默认值。
const List<String> qualityOrder = ['128k', '320k', 'flac', 'flac24bit', 'master'];

/// 取链时的音质尝试顺序：先试用户选的那个，再按从高到低补上脚本声明的其它音质。
///
/// 音质不是歌曲属性而是脚本那边能拿到什么：野草源只给 128k，用户选了 320k
/// 脚本就返回空（宿主报「脚本没有返回播放直链」），退一档再试就好。
/// 不在 [qualityOrder] 里的音质（ape/wav）排在最后。
List<String> qualityTries(String quality, List<String> declared) {
  final rest = declared.where((item) => item != quality).toList()
    ..sort((a, b) => qualityOrder.indexOf(b).compareTo(qualityOrder.indexOf(a)));
  return [quality, ...rest];
}

// ---------------------------------------------------------------------------
// 通用小工具
// ---------------------------------------------------------------------------

class OnlineApiException implements Exception {
  OnlineApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, dynamic> _asMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : const <String, dynamic>{};

Map<String, dynamic> _asJsonObject(String body, String what) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw OnlineApiException('$what 返回的不是合法 JSON（${e.message}）');
  }
  if (decoded is! Map) throw OnlineApiException('$what 返回的不是 JSON 对象');
  return decoded.map((key, value) => MapEntry('$key', value));
}

/// http 包的 `Response.body` 在响应没声明 charset 时按 latin1 解，中文会乱码。
/// 先按 utf8 严格解，失败再退 gbk —— 国内这几个老接口不是 utf8 就是 gbk。
String _decodeBody(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return gbk.decode(bytes, allowMalformed: true);
  }
}

Future<http.Response> _send(Future<http.Response> Function() request) async {
  try {
    final response = await request().timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw OnlineApiException('HTTP ${response.statusCode}');
    }
    return response;
  } on TimeoutException {
    throw OnlineApiException('请求超时');
  } on SocketException catch (e) {
    throw OnlineApiException('网络不可达：${e.osError?.message ?? '连接失败'}');
  } on http.ClientException catch (e) {
    throw OnlineApiException('网络异常：${e.message}');
  }
}

Map<String, String> _headers(Map<String, String>? extra) => {
  'User-Agent': _lxUserAgent,
  ...?extra,
};

Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
    _send(() => http.get(uri, headers: _headers(headers)));

/// 表单 POST。咪咕的 resourceinfo.do 只认 form。
Future<http.Response> _post(
  Uri uri,
  Map<String, String> body, {
  Map<String, String>? headers,
}) => _send(() => http.post(uri, body: body, headers: _headers(headers)));

/// JSON POST。酷狗批量详情、QQ 的 musicu.fcg 都是 JSON body。
Future<Map<String, dynamic>> _postJson(
  Uri uri,
  Object body,
  String what, {
  Map<String, String>? headers,
}) async {
  final response = await _send(
    () => http.post(
      uri,
      headers: _headers({'Content-Type': 'application/json', ...?headers}),
      body: jsonEncode(body),
    ),
  );
  return _asJsonObject(_decodeBody(response.bodyBytes), what);
}

/// HTML 实体解码。酷我返回的歌名里带 `&nbsp;` 之类的实体。
/// ponytail: 只处理常见实体，够用；真遇到冷门实体再加表。
String decodeName(String value) {
  if (value.isEmpty) return '';
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      );
}

String _formatPlayTime(int? seconds) {
  if (seconds == null || seconds <= 0) return '00:00';
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

String _sizeFormat(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
  return '${bytes}B';
}

int _asInt(Object? value) => (num.tryParse('$value') ?? 0).toInt();

/// 按 [fields] 的 quality -> (size 字段, hash 字段) 从 [item] 里挑出
/// 非零音质，返回按 [qualityOrder] 排好序的 types（酷狗两处解析共用）。
List<Map<String, String>> _qualitysOf(
  Map<String, dynamic> item,
  Map<String, (String, String)> fields,
) {
  final byType = <String, Map<String, String>>{};
  for (final entry in fields.entries) {
    final size = _asInt(item[entry.value.$1]);
    final hash = '${item[entry.value.$2] ?? ''}';
    if (size != 0 && hash.isNotEmpty) {
      byType[entry.key] = {
        'type': entry.key,
        'size': _sizeFormat(size),
        'hash': hash,
      };
    }
  }
  return [
    for (final quality in qualityOrder)
      if (byType[quality] != null) byType[quality]!,
  ];
}

/// 全量列表的第 [page] 页（每页 [pageSize] 条）。歌单详情类接口都是
/// 一次拉全量，这里统一切片。
List<OnlineTrack> _slicedPage(List<OnlineTrack> list, int page, int pageSize) {
  final start = (page - 1) * pageSize;
  if (start >= list.length) return const [];
  return list.sublist(start, (start + pageSize).clamp(start, list.length));
}

/// 歌手列表格式化（lx `formatSingerName`）：取每个 name 用「、」连接，
/// 非列表直接当字符串。酷狗 Singers / QQ singer / 网易 ar 都是 `[{name}]`。
String _formatSingerName(Object? singers) {
  if (singers is List) {
    return decodeName(
      singers
          .map((singer) => '${_asMap(singer)['name'] ?? ''}')
          .where((name) => name.isNotEmpty)
          .join('、'),
    );
  }
  return decodeName('${singers ?? ''}');
}

// ---------------------------------------------------------------------------
// 第三方源签名/加密（QQ zzcSign、网易 eapi / linuxapi）
// ---------------------------------------------------------------------------

/// QQ 音乐 `zzcSign`（lx `musicSdk/tx/utils/crypto.js`）：SHA1 按固定下标拆成
/// 前后两段，中段逐字节异或后 base64 去掉 `/\+=`，整体小写。
/// 注意 SHA1 hex 是 40 字符，前段下标 40 越界，lx 里 JS 取到 undefined
/// 拼接成空串——这里保持同口径。
String txZzcSign(String text) {
  const part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19];
  const part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5];
  const scrambleValues = [
    89, 39, 179, 150, 218, 82, 58, 252, 177, 52,
    186, 123, 120, 64, 242, 133, 143, 161, 121, 179,
  ];
  final hash = sha1.convert(utf8.encode(text)).toString();
  String pick(List<int> indexes) => [
    for (final index in indexes) index < hash.length ? hash[index] : '',
  ].join();
  final scrambled = [
    for (var i = 0; i < scrambleValues.length; i++)
      scrambleValues[i] ^ int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16),
  ];
  final b64 = base64.encode(scrambled).replaceAll(RegExp(r'[\\/+=]'), '');
  return 'zzc${pick(part1Indexes)}$b64${pick(part2Indexes)}'.toLowerCase();
}

/// AES-128-ECB（PKCS7），输出大写 hex。网易 eapi / linuxapi 共用。
String _aesEcbHexUpper(List<int> plain, String key) {
  final bytes =
      Encrypter(AES(Key.fromUtf8(key), mode: AESMode.ecb))
          .encryptBytes(plain)
          .bytes;
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

/// 网易 eapi（lx `musicSdk/wy/utils/crypto.js`）：请求体摘要拼进明文再整体
/// 加密，hex 大写后作为 form 的 `params` 字段。
String wyEapiParams(String url, Object data) {
  final text = jsonEncode(data);
  final digest = md5
      .convert(utf8.encode('nobody${url}use${text}md5forencrypt'))
      .toString();
  return _aesEcbHexUpper(
    utf8.encode('$url-36cd479b6b5-$text-36cd479b6b5-$digest'),
    'e82ckenh8dichen8',
  );
}

/// 网易 linuxapi：整个 `{method, url, params}` JSON 加密，form 字段是
/// `eparams`。响应是明文 JSON，无需解密（lx 请求层也不解）。
String wyLinuxParams(Object object) =>
    _aesEcbHexUpper(utf8.encode(jsonEncode(object)), 'rFgB&h#%2?^eDg:Q');

// ---------------------------------------------------------------------------
// 搜索结果
// ---------------------------------------------------------------------------

/// 一条在线搜索结果。
///
/// 字段刻意保持 lx-music 的「旧格式 musicInfo」形状，[toMusicInfo] 才能原样
/// POST 给聚合接口 —— 服务端解析的就是这套字段。
class OnlineTrack {
  OnlineTrack({
    required this.source,
    required this.songmid,
    required this.name,
    required this.singer,
    required this.albumName,
    required this.albumId,
    required this.interval,
    required this.types,
    this.img,
    this.extra = const {},
  });

  final String source; // 'kw' | 'kg' | 'tx' | 'wy' | 'mg'
  final String songmid;
  final String name;
  final String singer;
  final String albumName;
  final String albumId;
  final String interval; // '04:29'

  /// 搜索结果自带的封面。酷我搜索不带，得由
  /// [OnlineApiClient.fetchPicUrl] 现取，所以这里允许为空。
  final String? img;

  /// `[{type: '320k', size: '8.1M'}]`
  final List<Map<String, String>> types;

  /// 源特有字段（mg 的 copyrightId / lrcUrl / mrcUrl / trcUrl）。
  final Map<String, dynamic> extra;

  /// 加 `online_` 前缀，避免和本地曲目 id 撞车。
  String get id => 'online_${source}_$songmid';

  List<String> get qualitys => types
      .map((type) => type['type'] ?? '')
      .where((type) => type.isNotEmpty)
      .toList();

  Map<String, dynamic> toMusicInfo() => {
    'name': name,
    'singer': singer,
    'source': source,
    'songmid': songmid,
    'interval': interval,
    'albumName': albumName,
    'img': img ?? '',
    'typeUrl': <String, dynamic>{},
    'albumId': albumId,
    'types': types,
    '_types': {
      for (final type in types)
        type['type']!: {'size': type['size'] ?? ''},
    },
    ...extra,
  };
}

/// 一条在线歌单搜索结果。
class OnlinePlaylist {
  OnlinePlaylist({
    required this.source,
    required this.id,
    required this.name,
    required this.creator,
    required this.pic,
    required this.songCount,
    required this.playCount,
    this.intro,
  });

  final String source; // 'kw' | 'kg' | 'tx' | 'wy' | 'mg'
  final String id;
  final String name;
  final String creator;
  final String pic;
  final int songCount;
  final int playCount;
  final String? intro;

  String get songCountFormatted => '$songCount 首';

  String get playCountFormatted {
    if (playCount >= 100000000) {
      return '${(playCount / 100000000).toStringAsFixed(1)}亿播放';
    }
    if (playCount >= 10000) {
      return '${(playCount / 10000).toStringAsFixed(1)}万播放';
    }
    if (playCount > 0) return '$playCount 播放';
    return '';
  }
}

// ---------------------------------------------------------------------------
// 本地设置
// ---------------------------------------------------------------------------

/// 在线音乐的本地设置：自定义源脚本（可多个）、默认音质、下载目录。
class OnlineSettings {
  static const String _fileName = 'online_music_settings.json';

  /// 脚本正文单独存文件：脚本动辄几十 KB，塞进设置 JSON 不好读也不好改。
  static const String _scriptsFileName = 'online_music_scripts.json';

  /// 老版本的单脚本文件，读到就迁移成脚本列表。
  static const String _legacyScriptFileName = 'online_music_script.js';

  /// 已导入的自定义源脚本。可以导入多个，但同一时间只有一个生效。
  final ValueNotifier<List<LxScriptEntry>> scripts =
      ValueNotifier(const <LxScriptEntry>[]);

  /// 生效脚本的下标（单选）：只有 [currentScript] 会被加载使用。
  final ValueNotifier<int> activeScript = ValueNotifier(0);

  final ValueNotifier<String> quality = ValueNotifier('128k');

  /// 上次选中的搜索音源（单选模式），默认酷我。
  final ValueNotifier<String> source = ValueNotifier('kw');

  /// 下载目录。存 URI 字符串：桌面是 `file://`，Android 是 `content://`，
  /// iOS 是 `urlbookmark://`（只有 URI 才能跨重启恢复访问权限）。
  final ValueNotifier<String> downloadDir = ValueNotifier('');

  File get _file => File('${appSupportDir.path}/$_fileName');

  File get _scriptsFile => File('${appSupportDir.path}/$_scriptsFileName');

  File get _legacyScriptFile =>
      File('${appSupportDir.path}/$_legacyScriptFileName');

  bool get hasScript => scripts.value.isNotEmpty;

  /// 生效脚本的下标；删掉脚本后可能越界，读的时候夹回合法范围。
  int get activeScriptIndex {
    final count = scripts.value.length;
    if (count == 0) return 0;
    final index = activeScript.value;
    if (index < 0) return 0;
    return index >= count ? count - 1 : index;
  }

  /// 当前生效的脚本；一个都没导入时是 null。
  LxScriptEntry? get currentScript {
    final list = scripts.value;
    return list.isEmpty ? null : list[activeScriptIndex];
  }

  /// 选中某个脚本，它成为唯一生效的源。
  Future<void> setActiveScript(int index) async {
    activeScript.value = index;
    await save();
  }

  /// 导入脚本：同链接就替换原条目，否则追加到末尾。
  Future<void> addScript(LxScriptEntry entry) async {
    final list = [...scripts.value];
    final index = entry.url.isEmpty
        ? -1
        : list.indexWhere((item) => item.url == entry.url);
    if (index >= 0) {
      list[index] = entry;
    } else {
      list.add(entry);
      // 第一个导入的脚本直接生效，省得再点一次。
      if (list.length == 1) activeScript.value = 0;
    }
    scripts.value = list;
    await _saveScripts();
  }

  Future<void> removeScript(int index) async {
    final list = [...scripts.value]..removeAt(index);
    scripts.value = list;
    // 删掉的是生效的那个（或它前面的），下标跟着往前挪一格。
    if (activeScript.value >= index && activeScript.value > 0) {
      activeScript.value = activeScript.value - 1;
    }
    await _saveScripts();
    await save();
  }

  Future<void> load() async {
    try {
      var legacyName = '';
      if (_file.existsSync()) {
        final map = _asMap(jsonDecode(await _file.readAsString()));
        quality.value = map['quality'] as String? ?? '128k';
        source.value = map['source'] as String? ?? 'kw';
        downloadDir.value = map['downloadDir'] as String? ?? '';
        activeScript.value = (map['activeScript'] as num?)?.toInt() ?? 0;
        legacyName = map['scriptName'] as String? ?? '';
      }
      await _loadScripts(legacyName);
    } catch (e) {
      logger.output('[online] 设置读取失败: $e');
    }
  }

  /// 读脚本列表；老版本的单脚本文件还在就迁进来，再删掉它。
  Future<void> _loadScripts(String legacyName) async {
    if (_scriptsFile.existsSync()) {
      final decoded = jsonDecode(await _scriptsFile.readAsString());
      final list = <LxScriptEntry>[];
      for (final item in decoded is List ? decoded : const []) {
        final entry = LxScriptEntry.fromJson(item);
        if (entry != null) list.add(entry);
      }
      scripts.value = list;
      return;
    }
    if (!_legacyScriptFile.existsSync()) return;
    scripts.value = [
      LxScriptEntry.fromScript(
        _legacyScriptFile.readAsStringSync(),
        name: legacyName.isEmpty ? 'custom' : legacyName,
      ),
    ];
    await _saveScripts();
    await _legacyScriptFile.delete();
  }

  Future<void> save() async {
    try {
      await _file.writeAsString(
        jsonEncode({
          'quality': quality.value,
          'source': source.value,
          'downloadDir': downloadDir.value,
          'activeScript': activeScript.value,
        }),
      );
    } catch (e) {
      logger.output('[online] 设置写入失败: $e');
    }
  }

  Future<void> _saveScripts() async {
    try {
      await _scriptsFile.writeAsString(
        jsonEncode([for (final entry in scripts.value) entry.toJson()]),
      );
    } catch (e) {
      logger.output('[online] 脚本列表写入失败: $e');
    }
  }
}

final OnlineSettings onlineSettings = OnlineSettings();

// ---------------------------------------------------------------------------
// 搜索器
// ---------------------------------------------------------------------------

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

final Map<String, OnlineSearcher> onlineSearchers = {
  'kw': KwSearcher(),
  'kg': KgSearcher(),
  'tx': TxSearcher(),
  'wy': WySearcher(),
  'mg': MgSearcher(),
};

/// 酷我。接口与解析规则取自 lx-music 的 `musicSdk/kw/musicSearch.js`。
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
    final response = await _get(Uri.parse('https://search.kuwo.cn/r.s?$query'));
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '酷我搜索');
    return parseAbslist(json['abslist']);
  }

  /// 解析酷我搜索响应的 `abslist`。
  List<OnlineTrack> parseAbslist(Object? abslist) {
    final result = <OnlineTrack>[];
    for (final item in (abslist as List?) ?? const []) {
      final info = _asMap(item);
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
          interval: _formatPlayTime(int.tryParse('${info['DURATION']}')),
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
    final response = await _get(Uri.parse('https://search.kuwo.cn/r.s?$query'));
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '酷我歌单搜索');
    return parsePlaylistAbslist(json['abslist']);
  }

  List<OnlinePlaylist> parsePlaylistAbslist(Object? abslist) {
    final result = <OnlinePlaylist>[];
    for (final item in (abslist as List?) ?? const []) {
      final info = _asMap(item);
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
    final response = await _get(
      Uri.parse(
        'https://m.kuwo.cn/newh5app/wapi/api/www/playlist/playListInfo'
        '?pid=$playlistId&pn=$page&rn=$pageSize',
      ),
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '酷我歌单详情');
    final data = _asMap(json['data']);
    final musicList = (data['musicList'] as List?) ?? const [];
    final result = <OnlineTrack>[];
    for (final item in musicList) {
      final info = _asMap(item);
      final musicrid = '${info['musicrid'] ?? ''}';
      final songmid = musicrid.isNotEmpty
          ? musicrid.replaceFirst('MUSIC_', '')
          : '${info['rid'] ?? ''}';
      if (songmid.isEmpty) continue;
      final duration = int.tryParse('${info['duration'] ?? 0}') ?? 0;
      var pic = '${info['pic'] ?? info['albumpic'] ?? ''}';

      result.add(
        OnlineTrack(
          source: source,
          songmid: songmid,
          name: decodeName('${info['name'] ?? ''}'),
          singer: decodeName('${info['artist'] ?? ''}'),
          albumName: decodeName('${info['album'] ?? ''}'),
          albumId: '${info['albumid'] ?? ''}',
          interval: _formatPlayTime(duration),
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

/// 咪咕。接口、签名与解析规则取自 lx-music 的 `musicSdk/mg/musicSearch.js`。
class MgSearcher implements OnlineSearcher {
  @override
  String get source => 'mg';

  @override
  String get label => '咪咕';

  @override
  int get pageSize => 20;

  static const String deviceId = '963B7AA0D21511ED807EE5846EC87D20';
  static const String _signatureMd5 =
      '6cdc72a439cef99a3418d2a78aa28c73';
  static const String _signatureTail = 'yyapp2d16148780a1dcc7408e06336b98cfd50';

  /// 服务端要求的签名：`md5(关键词 + 常量 + 常量 + deviceId + 毫秒时间戳)`。
  static String buildSign(String keyword, String timestamp) => md5
      .convert(
        utf8.encode(
          '$keyword$_signatureMd5$_signatureTail$deviceId$timestamp',
        ),
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
    final response = await _get(
      Uri.parse('https://jadeite.migu.cn/music_search/v3/search/searchAll?$query'),
      headers: {
        'uiVersion': 'A_music_3.6.1',
        'deviceId': deviceId,
        'timestamp': timestamp,
        'sign': buildSign(keyword, timestamp),
        'channel': '0146921',
        'User-Agent': _mgUserAgent,
      },
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '咪咕搜索');
    if (json['code'] != '000000') {
      throw OnlineApiException('咪咕搜索失败（code=${json['code']}）');
    }

    return parseResultList(_asMap(json['songResultData'])['resultList']);
  }

  /// 解析咪咕搜索响应的 `songResultData.resultList`（二维数组）。
  List<OnlineTrack> parseResultList(Object? resultList) {
    final result = <OnlineTrack>[];
    final seen = <String>{};
    for (final group in (resultList as List?) ?? const []) {
      if (group is! List) continue;
      for (final item in group) {
        final data = _asMap(item);
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
            singer: _formatSingerName(data['singerList']),
            albumName: decodeName('${data['album'] ?? ''}'),
            albumId: '${data['albumId'] ?? ''}',
            interval: _formatPlayTime(int.tryParse('${data['duration']}')),
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
      final item = _asMap(raw);
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
        'size': _sizeFormat(int.tryParse('${item['asize'] ?? item['isize']}')),
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
    final response = await _get(
      Uri.parse('https://jadeite.migu.cn/music_search/v3/search/searchAll?$query'),
      headers: {
        'uiVersion': 'A_music_3.6.1',
        'deviceId': deviceId,
        'timestamp': timestamp,
        'sign': buildSign(keyword, timestamp),
        'channel': '0146921',
        'User-Agent': _mgUserAgent,
      },
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '咪咕歌单搜索');
    if (json['code'] != '000000') {
      throw OnlineApiException('咪咕歌单搜索失败（code=${json['code']}）');
    }
    final sld = _asMap(json['songListResultData']);
    final list = (sld['result'] as List?) ?? const [];
    final result = <OnlinePlaylist>[];
    for (final item in list) {
      final data = _asMap(item);
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
    final response = await _get(
      Uri.parse(
        'https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0'
        '?playlistId=$playlistId&pageNo=$page&pageSize=$pageSize',
      ),
      headers: {
        'User-Agent': _mgUserAgent,
      },
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '咪咕歌单详情');
    final data = _asMap(json['data']);
    final songList = (data['songList'] as List?) ?? const [];
    final result = <OnlineTrack>[];
    for (final item in songList) {
      final track = _asMap(item);
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
          singer: _formatSingerName(track['singerList']),
          albumName: decodeName('${track['album'] ?? ''}'),
          albumId: '${track['albumId'] ?? ''}',
          interval: _formatPlayTime(int.tryParse('${track['duration']}')),
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

// ---------------------------------------------------------------------------
// 酷狗
// ---------------------------------------------------------------------------

/// 酷狗。接口与解析规则取自 lx-music 的 `musicSdk/kg/musicSearch.js`
/// 与 `songList.js`。搜索无加密；歌单详情抓页面 HTML 拿 hash 列表后
/// 走 gateway 批量接口换详情。
class KgSearcher implements OnlineSearcher {
  @override
  String get source => 'kg';

  @override
  String get label => '酷狗';

  @override
  int get pageSize => 30;

  /// 歌单详情一次拉全量再按页切片，缓存整张歌单避免每页重抓 HTML。
  /// ponytail: 只放内存，进程退出即失效。
  final Map<String, List<OnlineTrack>> _detailCache = {};

  @override
  Future<List<OnlineTrack>> search(String keyword, {int page = 1}) async {
    final response = await _get(
      Uri.parse(
        'http://songsearch.kugou.com/song_search_v2?platform=AndroidFilter'
        '&iscorrection=1&keyword=${Uri.encodeComponent(keyword)}'
        '&hifiquality=0&pagesize=$pageSize&PrivilegeFilter=0&page=$page',
      ),
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '酷狗搜索');
    if ('${json['error_code']}' != '0') {
      throw OnlineApiException('酷狗搜索失败（error_code=${json['error_code']}）');
    }
    return _parseSongList((_asMap(json['data'])['lists'] as List?) ?? const []);
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
      final types = _qualitysOf(item, const {
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
          singer: _formatSingerName(item['Singers']),
          albumName: decodeName('${item['AlbumName'] ?? ''}'),
          albumId: '${item['AlbumID'] ?? ''}',
          interval: _formatPlayTime(int.tryParse('${item['Duration']}')),
          types: types,
          extra: {'hash': hash, 'albumAudioId': '${item['MixSongID'] ?? ''}'},
        ),
      );
    }

    for (final raw in list) {
      final item = _asMap(raw);
      add(item);
      for (final child in (item['Grp'] as List?) ?? const []) {
        add(_asMap(child));
      }
    }
    return result;
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(
    String keyword, {
    int page = 1,
  }) async {
    final response = await _get(
      Uri.parse(
        'http://msearchretry.kugou.com/api/v3/search/special'
        '?keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=20'
        '&showtype=10&filter=0&version=7910&sver=2',
      ),
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '酷狗歌单搜索');
    if ('${json['errcode']}' != '0') {
      throw OnlineApiException('酷狗歌单搜索失败（errcode=${json['errcode']}）');
    }
    final result = <OnlinePlaylist>[];
    for (final raw in (_asMap(json['data'])['info'] as List?) ?? const []) {
      final item = _asMap(raw);
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

  @override
  Future<List<OnlineTrack>> getPlaylistTracks(
    String playlistId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    var all = _detailCache[playlistId];
    // 成功才写缓存：失败不缓存，重试还能重新拉。
    all ??= await _fetchPlaylistDetail(playlistId);
    _detailCache[playlistId] = all;
    return _slicedPage(all, page, pageSize);
  }

  /// specialid 详情：`…single/{id}-5-9999.html` 页面里的 `global.data = […]`
  /// 只有 hash，拿去按 100/批换完整详情（lx `getListDetailBySpecialId` +
  /// `getMusicInfos`）。我们的歌单 id 都来自自家搜索，只处理这一个分支。
  Future<List<OnlineTrack>> _fetchPlaylistDetail(String specialId) async {
    final response = await _get(
      Uri.parse(
        'http://www2.kugou.kugou.com/yueku/v9/special/single/'
        '$specialId-5-9999.html',
      ),
    );
    final match = RegExp(
      r'global\.data = (\[.+\]);',
    ).firstMatch(_decodeBody(response.bodyBytes));
    if (match == null) throw OnlineApiException('酷狗歌单详情解析失败');
    final hashes = <String>[];
    final seen = <String>{};
    for (final raw in jsonDecode(match.group(1)!) as List) {
      final hash = '${_asMap(raw)['hash'] ?? ''}';
      if (hash.isNotEmpty && seen.add(hash)) hashes.add(hash);
    }

    final result = <OnlineTrack>[];
    final ids = <String>{};
    for (var start = 0; start < hashes.length; start += 100) {
      final json = await _postJson(
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
        final item = _asMap(group.first);
        final audio = _asMap(item['audio_info']);
        final audioId = '${audio['audio_id'] ?? ''}';
        if (audioId.isEmpty || !ids.add(audioId)) continue;
        final types = _qualitysOf(audio, const {
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
            albumName: decodeName(_asMap(item['album_info'])['album_name'] ?? ''),
            albumId: '${_asMap(item['album_info'])['album_id'] ?? ''}',
            interval: _formatPlayTime(_asInt(audio['timelength']) ~/ 1000),
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

// ---------------------------------------------------------------------------
// QQ 音乐
// ---------------------------------------------------------------------------

/// QQ 音乐。接口与签名规则取自 lx-music 的 `musicSdk/tx/musicSearch.js`
/// 与 `songList.js`。搜索走 musics.fcg + zzcSign；歌单搜索/详情是普通
/// GET/POST，不需要签名。
class TxSearcher implements OnlineSearcher {
  @override
  String get source => 'tx';

  @override
  String get label => 'QQ音乐';

  @override
  int get pageSize => 50;

  /// 同 [KgSearcher._detailCache]：详情全量拉一次再切片。
  final Map<String, List<OnlineTrack>> _detailCache = {};

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
      final json = await _postJson(
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
      if (json['code'] == 0 && entry is Map && _asMap(entry)['code'] == 0) {
        return _asMap(_asMap(entry)['data']);
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
    final song = _asMap(_asMap(_asMap(data)['body'])['song']);
    return _parseSongList((song['list'] as List?) ?? const []);
  }

  /// 条目质量在 `file` 里：size_128mp3 / size_320mp3 / size_flac / size_hires。
  List<OnlineTrack> _parseSongList(List list) {
    final result = <OnlineTrack>[];
    for (final raw in list) {
      final item = _asMap(raw);
      final file = _asMap(item['file']);
      final mediaMid = '${file['media_mid'] ?? ''}';
      if (mediaMid.isEmpty) continue;
      final types = <String, Map<String, String>>{
        for (final entry in {
          '128k': 'size_128mp3',
          '320k': 'size_320mp3',
          'flac': 'size_flac',
          'flac24bit': 'size_hires',
        }.entries)
          if (_asInt(file[entry.value]) != 0)
            entry.key: {'type': entry.key, 'size': _sizeFormat(_asInt(file[entry.value]))},
      };
      if (types.isEmpty) continue;
      final album = _asMap(item['album']);
      final albumMid = '${album['mid'] ?? ''}';
      final singers = item['singer'];
      // 无专辑（或专辑名是占位"空"）时退歌手图，口径同 lx。
      final String img;
      if (albumMid.isEmpty || albumMid == '空') {
        final first = singers is List && singers.isNotEmpty
            ? _asMap(singers.first)['mid']
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
          singer: _formatSingerName(singers),
          albumName: decodeName('${album['name'] ?? ''}'),
          albumId: albumMid,
          interval: _formatPlayTime(int.tryParse('${item['interval']}')),
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
    final response = await _get(
      Uri.parse(
        'http://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist'
        '?page_no=${page - 1}&num_per_page=20&format=json'
        '&query=${Uri.encodeComponent(keyword)}'
        '&remoteplace=txt.yqq.playlist&inCharset=utf8&outCharset=utf-8',
      ),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
        'Referer': 'http://y.qq.com/portal/search.html',
      },
    );
    final json = _asJsonObject(_decodeBody(response.bodyBytes), 'QQ音乐歌单搜索');
    if (json['code'] != 0) {
      throw OnlineApiException('QQ音乐歌单搜索失败（code=${json['code']}）');
    }
    final result = <OnlinePlaylist>[];
    for (final raw in (_asMap(json['data'])['list'] as List?) ?? const []) {
      final item = _asMap(raw);
      final id = '${item['dissid'] ?? ''}';
      if (id.isEmpty) continue;
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${item['dissname'] ?? ''}'),
          creator: decodeName(_asMap(item['creator'])['name'] ?? ''),
          pic: '${item['imgurl'] ?? ''}',
          songCount: int.tryParse('${item['song_count'] ?? 0}') ?? 0,
          playCount: int.tryParse('${item['listennum'] ?? 0}') ?? 0,
          intro: decodeName('${item['introduction'] ?? ''}').replaceAll('<br>', '\n'),
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
    var all = _detailCache[playlistId];
    // 成功才写缓存：失败不缓存，重试还能重新拉。
    all ??= await _fetchPlaylistDetail(playlistId);
    _detailCache[playlistId] = all;
    return _slicedPage(all, page, pageSize);
  }

  /// 歌单详情：fcg_ucc 接口优先，code 不对退 musicu.fcg（lx `tx/songList.js`
  /// 的 getListDetail / getListDetail2）。两个接口都一次拉全量。
  Future<List<OnlineTrack>> _fetchPlaylistDetail(String dissId) async {
    final primary = _asJsonObject(
      _decodeBody(
        (await _get(
          Uri.parse(
            'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg'
            '?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=$dissId'
            '&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8'
            '&notice=0&platform=yqq.json&needNewCode=0',
          ),
          headers: {
            'Origin': 'https://y.qq.com',
            'Referer': 'https://y.qq.com/n/yqq/playsquare/$dissId.html',
          },
        )).bodyBytes,
      ),
      'QQ音乐歌单详情',
    );
    final cdlist = (primary['cdlist'] as List?) ?? const [];
    if (primary['code'] == 0 && primary['subcode'] == 0 && cdlist.isNotEmpty) {
      return _parseSongList((_asMap(cdlist.first)['songlist'] as List?) ?? const []);
    }

    final fallback = await _postJson(
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
    final req1 = _asMap(fallback['req_1']);
    if (fallback['code'] != 0 || req1['code'] != 0) {
      throw OnlineApiException('QQ音乐歌单详情失败（code=${req1['code'] ?? fallback['code']}）');
    }
    return _parseSongList((_asMap(req1['data'])['songlist'] as List?) ?? const []);
  }
}

// ---------------------------------------------------------------------------
// 网易云音乐
// ---------------------------------------------------------------------------

/// 网易。接口与加密规则取自 lx-music 的 `musicSdk/wy/musicSearch.js` 与
/// `songList.js`：搜索/歌单搜索走 eapi，歌单详情走 linuxapi。
/// 请求体要加密，响应是明文 JSON（lx 请求层同样不解密）。
class WySearcher implements OnlineSearcher {
  @override
  String get source => 'wy';

  @override
  String get label => '网易';

  @override
  int get pageSize => 30;

  /// 同 [KgSearcher._detailCache]：详情全量拉一次再切片。
  final Map<String, List<OnlineTrack>> _detailCache = {};

  static const String _wyUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/60.0.3112.90 Safari/537.36';

  /// eapi 请求：POST form，只有一个加密后的 `params` 字段。
  Future<Map<String, dynamic>> _eapi(String apiUrl, Object data) async {
    final response = await _post(
      Uri.parse('http://interface.music.163.com/eapi/batch'),
      {'params': wyEapiParams(apiUrl, data)},
      headers: {'User-Agent': _wyUserAgent, 'origin': 'https://music.163.com'},
    );
    return _asJsonObject(_decodeBody(response.bodyBytes), '网易接口');
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
    for (final raw in (_asMap(json['data'])['resources'] as List?) ?? const []) {
      final item = _asMap(_asMap(_asMap(raw)['baseInfo'])['simpleSongData']);
      if (item.isEmpty) continue;
      final track = _parseTrack(item, _asMap(item['privilege']));
      if (track != null) result.add(track);
    }
    return result;
  }

  /// lx 原实现是 switch 贯穿 fallthrough：高音质命中时低音质全都要，
  /// hires 另看 maxBrLevel。这里按 qualityOrder 顺序等价重建。
  OnlineTrack? _parseTrack(Map<String, dynamic> item, Map<String, dynamic> privilege) {
    final maxbr = _asInt(privilege['maxbr']);
    final hires = '${privilege['maxBrLevel'] ?? ''}' == 'hires';
    String? sizeOf(String field) {
      final bytes = _asInt(_asMap(item[field])['size']);
      return bytes > 0 ? _sizeFormat(bytes) : null;
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
    final al = _asMap(item['al']);
    final pic = '${al['picUrl'] ?? ''}';
    return OnlineTrack(
      source: source,
      songmid: '${item['id'] ?? ''}',
      name: decodeName('${item['name'] ?? ''}'),
      singer: _formatSingerName(item['ar']),
      albumName: decodeName('${al['name'] ?? ''}'),
      albumId: '${al['id'] ?? ''}',
      interval: _formatPlayTime(_asInt(item['dt']) ~/ 1000),
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
    for (final raw in (_asMap(json['result'])['playlists'] as List?) ?? const []) {
      final item = _asMap(raw);
      final id = '${item['id'] ?? ''}';
      if (id.isEmpty) continue;
      result.add(
        OnlinePlaylist(
          source: source,
          id: id,
          name: decodeName('${item['name'] ?? ''}'),
          creator: decodeName(_asMap(item['creator'])['nickname'] ?? ''),
          pic: '${item['coverImgUrl'] ?? ''}',
          songCount: int.tryParse('${item['trackCount'] ?? 0}') ?? 0,
          playCount: int.tryParse('${item['playCount'] ?? 0}') ?? 0,
          intro: decodeName('${item['description'] ?? ''}'),
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
    var all = _detailCache[playlistId];
    // 成功才写缓存：失败不缓存，重试还能重新拉。
    all ??= await _fetchPlaylistDetail(playlistId);
    _detailCache[playlistId] = all;
    return _slicedPage(all, page, pageSize);
  }

  /// 歌单详情走 linuxapi 转发（lx `wy/songList.js`）。
  /// ponytail: trackIds 与 privileges 数量不一致（超长歌单详情被截断）时，
  /// lx 会退 weapi 批量详情（要 RSA no-padding），这里直接报错，真遇到再加。
  Future<List<OnlineTrack>> _fetchPlaylistDetail(String playlistId) async {
    final response = await _post(
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
    final json = _asJsonObject(_decodeBody(response.bodyBytes), '网易歌单详情');
    if (json['code'] != 200) {
      throw OnlineApiException('网易歌单详情失败（code=${json['code']}）');
    }
    final playlist = _asMap(json['playlist']);
    final trackIds = (playlist['trackIds'] as List?) ?? const [];
    final privileges = (json['privileges'] as List?) ?? const [];
    if (trackIds.isEmpty || trackIds.length != privileges.length) {
      throw OnlineApiException('歌单详情不完整（${trackIds.length}/${privileges.length}），暂不支持');
    }
    final tracks = (playlist['tracks'] as List?) ?? const [];
    final result = <OnlineTrack>[];
    for (var i = 0; i < privileges.length; i++) {
      final item = _asMap(i < tracks.length ? tracks[i] : null);
      if (item.isEmpty) continue;
      // pc 字段是云盘上传的修正信息，lx 同口径优先用它。
      final pc = _asMap(item['pc']);
      final al = _asMap(item['al']);
      final track = _parseTrack(
        {
          ...item,
          if (pc.isNotEmpty) ...{
            'name': '${pc['sn'] ?? item['name']}',
            'ar': pc['ar'] ?? item['ar'],
            'al': {...al, if (pc['alb'] != null) 'name': pc['alb']},
          },
        },
        _asMap(privileges[i]),
      );
      if (track != null) result.add(track);
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// 直链解析：交给自定义源脚本
// ---------------------------------------------------------------------------

/// 酷我歌词接口的加密参数：明文循环异或固定密钥 `yeelion` 后 base64。
String kuwoLyricParam(String rid) {
  final plain = utf8.encode(
    'user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_$rid',
  );
  final key = utf8.encode('yeelion');
  return base64.encode([
    for (var i = 0; i < plain.length; i++) plain[i] ^ key[i % key.length],
  ]);
}

/// 酷我歌词响应体：`tp=content\r\n…\r\n\r\n` + zlib 压缩的 gb18030 文本。
/// 头部是 ASCII，用 latin1 逐字节对照字符串下标即可定位压缩数据。
String decodeKuwoLyricBody(List<int> body) {
  final text = latin1.decode(body);
  final offset = text.startsWith('tp=content') ? text.indexOf('\r\n\r\n') : -1;
  if (offset < 0) return '';
  return gbk.decode(zlib.decode(body.sublist(offset + 4)), allowMalformed: true);
}

// ---------------------------------------------------------------------------
// 封面
// ---------------------------------------------------------------------------

/// 酷我封面接口（lx-music `musicSdk/kw/pic.js`）：响应体本身就是图片地址，
/// 没有封面时返回的是一句提示文本，不是 http 开头。
String parseKwPic(String body) {
  final text = body.trim();
  return text.startsWith('http') ? text : '';
}

/// 咪咕封面接口（lx-music `musicSdk/mg/pic.js`）：resourceinfo.do 返回的
/// `resource[].albumImgs[0].img`，相对路径补上 CDN 域名。
String parseMgPic(Object? resource) {
  for (final item in resource is List ? resource : const []) {
    final imgs = _asMap(item)['albumImgs'];
    for (final img in imgs is List ? imgs : const []) {
      final url = '${_asMap(img)['img'] ?? ''}';
      if (url.isEmpty) continue;
      return url.startsWith('http') ? url : 'http://d.musicapp.migu.cn$url';
    }
  }
  return '';
}

class OnlineApiClient {
  /// `source|songmid|quality` -> 直链。
  /// ponytail: 只放内存、上限 200 条；重启失效可接受，真要跨进程复用再落盘。
  final Map<String, String> _urlCache = {};
  static const int _urlCacheLimit = 200;

  /// 曲目 id -> 歌词原文（LRC）。歌词不会变，取到就一直用。
  final Map<String, String> _lyricCache = {};

  /// 曲目 id -> 封面地址。同样取到就一直用。
  final Map<String, String> _picCache = {};

  /// 同一首歌的封面会被播放条、列表、详情页同时问，在途请求按 id 去重。
  final Map<String, Future<String>> _picRequests = {};

  /// 脚本声明的音源 -> 可用音质。已经跑起来就直接返回缓存。
  Future<Map<String, List<String>>> fetchSources() async {
    final sources = await _ensureLoaded();
    return sources.map((source, info) => MapEntry(source, info.qualitys));
  }

  /// 从链接下载自定义源脚本正文（导入用）。
  Future<String> fetchScript(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw OnlineApiException('请输入 http(s) 开头的脚本链接');
    }
    final response = await _get(uri);
    final text = _decodeBody(response.bodyBytes);
    if (text.trim().isEmpty) throw OnlineApiException('脚本内容为空');
    return text;
  }

  Future<Map<String, LxSourceInfo>> _ensureLoaded() async {
    if (lxJsSources.isReady) return lxJsSources.sources;
    // 音源单选：只加载「音源设置」里选中的那个脚本。
    final script = onlineSettings.currentScript;
    if (script == null) return const {};
    try {
      return await lxJsSources.loadAll([script]);
    } on LxJsException catch (e) {
      throw OnlineApiException(e.message);
    }
  }

  /// 解析播放直链：把歌曲对象交给脚本的 request 事件，音质按
  /// [qualityTries] 的顺序依次退档重试。
  Future<String> resolveUrl({
    required OnlineTrack track,
    required String quality,
  }) async {
    final cacheKey = '${track.source}|${track.songmid}|$quality';
    final cached = _urlCache[cacheKey];
    if (cached != null) return cached;

    final sources = await _ensureLoaded();
    if (sources.isEmpty) {
      throw OnlineApiException('还没有导入自定义源脚本，请在「音源设置」里导入');
    }
    final info = sources[track.source];
    if (info == null) {
      // 音源由脚本自己声明：野草只声明 kw，播 mg 得切到另一个声明了 mg 的脚本。
      throw OnlineApiException(
        '自定义源脚本不支持音源 ${track.source}'
        '（已声明：${sources.keys.join('、')}）',
      );
    }

    Object? lastError;
    for (final candidate in qualityTries(quality, info.qualitys)) {
      try {
        final url = await lxJsSources.getMusicUrl(
          track.source,
          track.toMusicInfo(),
          candidate,
        );
        _cacheUrl(cacheKey, url);
        return url;
      } on LxJsException catch (e) {
        lastError = e;
        logger.output(
          '[online] ${track.source} ${track.name} @$candidate 解析失败: ${e.message}',
        );
      }
    }
    throw OnlineApiException('$lastError');
  }

  /// 取歌词。优先走脚本的 `lyric` action；脚本不支持就回退：`kw` 直接问酷我
  /// 歌词接口，`mg` 用搜索/歌单结果自带的 lrcUrl。取不到返回空串。
  Future<String> fetchLyric(OnlineTrack track) async {
    final cached = _lyricCache[track.id];
    if (cached != null) return cached;

    var lyric = '';
    try {
      final sources = await _ensureLoaded();
      if (sources[track.source]?.actions.contains('lyric') ?? false) {
        lyric = await lxJsSources.getLyric(track.source, track.toMusicInfo());
      }
    } on LxJsException catch (e) {
      logger.output('[online] ${track.source} ${track.name} 歌词获取失败: ${e.message}');
    }
    if (lyric.trim().isEmpty) lyric = await _fetchLyricFile(track);
    if (lyric.trim().isNotEmpty) _lyricCache[track.id] = lyric;
    return lyric;
  }

  /// 取封面。取不到返回空串（封面缺失不算错误，UI 退占位图）。
  ///
  /// 口径同 lx-music 的 `getPic`：结果里自带的 `img` 先用（咪咕搜索有 img3），
  /// 否则先问脚本的 `pic` action，再退回音源自己的实现 —— 酷我
  /// `artistpicserver`、咪咕 `resourceinfo.do` 的 albumImgs。
  Future<String> fetchPicUrl(OnlineTrack track) {
    final own = track.img;
    if (own != null && own.isNotEmpty) return Future.value(own);
    final cached = _picCache[track.id];
    if (cached != null) return Future.value(cached);
    return _picRequests.putIfAbsent(track.id, () async {
      try {
        final url = await _loadPic(track);
        // 失败不缓存：网断了一下不至于这轮一直没封面。
        if (url.isNotEmpty) _picCache[track.id] = url;
        return url;
      } finally {
        _picRequests.remove(track.id);
      }
    });
  }

  Future<String> _loadPic(OnlineTrack track) async {
    try {
      final sources = await _ensureLoaded();
      if (sources[track.source]?.actions.contains('pic') ?? false) {
        final url = await lxJsSources.getPic(track.source, track.toMusicInfo());
        if (url.isNotEmpty) return url;
      }
    } on LxJsException catch (e) {
      logger.output('[online] ${track.source} ${track.name} 封面获取失败: ${e.message}');
    }
    try {
      return switch (track.source) {
        'kw' => parseKwPic(
          _decodeBody(
            (await _get(
              Uri.parse(
                'http://artistpicserver.kuwo.cn/pic.web?corp=kuwo'
                '&type=rid_pic&pictype=500&size=500&rid=${track.songmid}',
              ),
            )).bodyBytes,
          ),
        ),
        'mg' => parseMgPic(
          _asJsonObject(
            _decodeBody(
              (await _post(
                Uri.parse(
                  'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/'
                  'resourceinfo.do?resourceType=2',
                ),
                {'resourceId': track.songmid},
              )).bodyBytes,
            ),
            '咪咕封面',
          )['resource'],
        ),
        _ => '',
      };
    } catch (e) {
      logger.output('[online] ${track.source} ${track.name} 封面获取失败: $e');
      return '';
    }
  }

  /// 回退取词：`kw` 的 songmid 就是酷我 rid，走酷我接口；其余（咪咕）没有
  /// 酷我 rid，只能用搜索/歌单结果里自带的 lrcUrl。
  Future<String> _fetchLyricFile(OnlineTrack track) async {
    if (track.source == 'kw') {
      try {
        final response = await _get(
          Uri.parse(
            'http://newlyric.kuwo.cn/newlyric.lrc'
            '?${kuwoLyricParam(track.songmid)}',
          ),
        );
        return decodeKuwoLyricBody(response.bodyBytes);
      } catch (e) {
        logger.output('[online] 酷我歌词获取失败: $e');
        return '';
      }
    }
    return _fetchMiguLyric(track);
  }

  /// 咪咕搜索/歌单结果里的 lrcUrl：可能是相对路径。
  Future<String> _fetchMiguLyric(OnlineTrack track) async {
    var url = '${track.extra['lrcUrl'] ?? ''}';
    if (url.isEmpty) return '';
    if (!url.startsWith('http')) url = 'http://d.musicapp.migu.cn$url';
    try {
      final response = await _get(
        Uri.parse(url),
        headers: {'User-Agent': _mgUserAgent},
      );
      return _decodeBody(response.bodyBytes);
    } catch (e) {
      logger.output('[online] 歌词下载失败: $e');
      return '';
    }
  }

  /// 脚本变了就重新加载（导入新脚本后调用）。
  Future<void> reload() async {
    await lxJsSources.unload();
    _urlCache.clear();
    _lyricCache.clear();
    _picCache.clear();
    _picRequests.clear();
  }

  void _cacheUrl(String key, String url) {
    _urlCache.remove(key);
    _urlCache[key] = url;
    while (_urlCache.length > _urlCacheLimit) {
      _urlCache.remove(_urlCache.keys.first);
    }
  }
}

final OnlineApiClient onlineApiClient = OnlineApiClient();

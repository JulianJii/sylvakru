// 在线音乐各接口共用的 HTTP 通道与解析小工具。
//
// 原本全挤在 online_music_api.dart 里，拆出来后成为音源实现与直链解析
// 共享的底层。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:http/http.dart' as http;

import 'package:sylvakru/online_music/api/online_models.dart';

/// lx-music 对**所有**请求都带这个 UA，酷我/咪咕的接口都依赖它。
const String lxUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/69.0.3497.100 Safari/537.36';

/// 咪咕专用 UA。
const String mgUserAgent =
    'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) '
    'AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30';

/// 与 lx-music 的默认请求超时保持一致。聚合接口走 Cloudflare，
/// 10s 实测偶发超时，15s 更稳。
const Duration requestTimeout = Duration(seconds: 15);

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

/// 把任意 JSON 值当成对象读；不是对象时给空 map。
Map<String, dynamic> asMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : const <String, dynamic>{};

/// 解析 JSON 对象，失败时抛出带上下文的 [OnlineApiException]。
Map<String, dynamic> asJsonObject(String body, String what) {
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
String decodeBody(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return gbk.decode(bytes, allowMalformed: true);
  }
}

/// 统一发请求 + 超时 + 把底层异常翻译成 [OnlineApiException]。
Future<http.Response> send(Future<http.Response> Function() request) async {
  try {
    final response = await request().timeout(requestTimeout);
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

Map<String, String> buildHeaders(Map<String, String>? extra) => {
  'User-Agent': lxUserAgent,
  ...?extra,
};

Future<http.Response> httpGet(Uri uri, {Map<String, String>? headers}) =>
    send(() => http.get(uri, headers: buildHeaders(headers)));

/// 表单 POST。咪咕的 resourceinfo.do 只认 form。
Future<http.Response> httpPost(
  Uri uri,
  Map<String, String> body, {
  Map<String, String>? headers,
}) => send(() => http.post(uri, body: body, headers: buildHeaders(headers)));

/// JSON POST。酷狗批量详情、QQ 的 musicu.fcg 都是 JSON body。
Future<Map<String, dynamic>> httpPostJson(
  Uri uri,
  Object body,
  String what, {
  Map<String, String>? headers,
}) async {
  final response = await send(
    () => http.post(
      uri,
      headers: buildHeaders({'Content-Type': 'application/json', ...?headers}),
      body: jsonEncode(body),
    ),
  );
  return asJsonObject(decodeBody(response.bodyBytes), what);
}

/// GET 后直接解析成 JSON 对象：各音源搜索/详情最常见的三连。
Future<Map<String, dynamic>> jsonGet(
  Uri uri,
  String what, {
  Map<String, String>? headers,
}) async {
  final response = await httpGet(uri, headers: headers);
  return asJsonObject(decodeBody(response.bodyBytes), what);
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

String formatPlayTime(int? seconds) {
  if (seconds == null || seconds <= 0) return '00:00';
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

String formatSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
  return '${bytes}B';
}

int asInt(Object? value) => (num.tryParse('$value') ?? 0).toInt();

/// 按 [fields] 的 quality -> (size 字段, hash 字段) 从 [item] 里挑出
/// 非零音质，返回按 [qualityOrder] 排好序的 types（酷狗两处解析共用）。
List<Map<String, String>> qualitysOf(
  Map<String, dynamic> item,
  Map<String, (String, String)> fields,
) {
  final byType = <String, Map<String, String>>{};
  for (final entry in fields.entries) {
    final size = asInt(item[entry.value.$1]);
    final hash = '${item[entry.value.$2] ?? ''}';
    if (size != 0 && hash.isNotEmpty) {
      byType[entry.key] = {
        'type': entry.key,
        'size': formatSize(size),
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
List<OnlineTrack> slicedPage(List<OnlineTrack> list, int page, int pageSize) {
  final start = (page - 1) * pageSize;
  if (start >= list.length) return const [];
  return list.sublist(start, (start + pageSize).clamp(start, list.length));
}

/// 歌手列表格式化（lx `formatSingerName`）：取每个 name 用「、」连接，
/// 非列表直接当字符串。酷狗 Singers / QQ singer / 网易 ar 都是 `[{name}]`。
String formatSingerName(Object? singers) {
  if (singers is List) {
    return decodeName(
      singers
          .map((singer) => '${asMap(singer)['name'] ?? ''}')
          .where((name) => name.isNotEmpty)
          .join('、'),
    );
  }
  return decodeName('${singers ?? ''}');
}

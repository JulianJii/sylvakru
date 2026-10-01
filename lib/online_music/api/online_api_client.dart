// 直链解析：交给自定义源脚本。
//
// 不再复刻某个具体接口，而是直接跑 lx-music 的「自定义源」脚本：Dart 复刻
// 宿主注入的 `window.lx`，用 QuickJS 原样执行用户 JS（见 lx_js/）。这里只做：
//   1. 等脚本 `lx.send('inited')`，拿到它声明的音源与音质
//   2. 把歌曲对象（lx 旧格式）交给脚本的 request 事件
//   3. 校验脚本返回的直链是 http(s) 且长度合规
//   4. 封面按 lx-music 的 `getPic` 口径取

import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/api/online_crypto.dart';
import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_settings.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_bridge.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';

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
    final response = await httpGet(uri);
    final text = decodeBody(response.bodyBytes);
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
          decodeBody(
            (await httpGet(
              Uri.parse(
                'http://artistpicserver.kuwo.cn/pic.web?corp=kuwo'
                '&type=rid_pic&pictype=500&size=500&rid=${track.songmid}',
              ),
            )).bodyBytes,
          ),
        ),
        'mg' => parseMgPic(
          asJsonObject(
            decodeBody(
              (await httpPost(
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
        final response = await httpGet(
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
      final response = await httpGet(
        Uri.parse(url),
        headers: {'User-Agent': mgUserAgent},
      );
      return decodeBody(response.bodyBytes);
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

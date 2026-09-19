// 自定义源脚本的生命周期管理：一个脚本 -> 一个 QuickJS 运行时。
// 可以同时导入多个脚本：取链按导入顺序依次尝试，前一个失败自动换下一个。
//
// 上层（OnlineApiClient）只跟这里打交道，不直接碰引擎。

import 'package:sylvakru/online_music/lx_js/lx_js_bridge.dart';

/// 一个已导入的自定义源脚本。
class LxScriptEntry {
  const LxScriptEntry({required this.name, required this.script, this.url = ''});

  /// 脚本名（导入时取链接末段）。
  final String name;

  /// 脚本正文。
  final String script;

  /// 导入用的下载链接；从老版本单脚本文件迁移过来的没有。
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'script': script};

  /// 反序列化；正文缺失的条目直接丢掉（返回 null）。
  static LxScriptEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final script = '${value['script'] ?? ''}';
    if (script.isEmpty) return null;
    final name = '${value['name'] ?? ''}';
    return LxScriptEntry(
      name: name.isEmpty ? 'custom' : name,
      script: script,
      url: '${value['url'] ?? ''}',
    );
  }
}

/// 一个加载成功的脚本：引擎 + 它声明的音源表。
class _LoadedScript {
  const _LoadedScript(this.engine, this.sources);

  final LxJsEngine engine;
  final Map<String, LxSourceInfo> sources;
}

class LxJsSourceManager {
  final List<_LoadedScript> _scripts = [];

  /// 最近一次加载失败的脚本（`名字：原因`），UI 拿它提示。
  final List<String> failures = [];

  /// 所有脚本声明的音源合并；同名音源取先导入的那个，顺序即优先级。
  Map<String, LxSourceInfo> get sources {
    final merged = <String, LxSourceInfo>{};
    for (final script in _scripts) {
      for (final entry in script.sources.entries) {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  bool get isReady => _scripts.isNotEmpty;

  /// 依次加载脚本。单个失败只记日志跳过，不影响其它脚本；
  /// 全部失败才抛出去，让调用方能把原因提示给用户。
  Future<Map<String, LxSourceInfo>> loadAll(List<LxScriptEntry> entries) async {
    await unload();
    Object? lastError;
    for (final entry in entries) {
      try {
        final engine = await LxJsEngine.load(
          script: entry.script,
          meta: LxScriptMeta.fromScript(entry.script, name: entry.name),
        );
        _scripts.add(_LoadedScript(engine, engine.sources));
      } catch (e) {
        lastError = e;
        failures.add('${entry.name}：${e is LxJsException ? e.message : e}');
        lxJsLog('脚本「${entry.name}」加载失败: $e');
      }
    }
    if (_scripts.isEmpty && lastError != null) {
      throw lastError is LxJsException
          ? lastError
          : LxJsException('$lastError');
    }
    return sources;
  }

  /// 取播放直链：按导入顺序试所有支持该音源的脚本，第一个成功即返回。
  Future<String> getMusicUrl(
    String source,
    Map<String, dynamic> musicInfo,
    String quality,
  ) async {
    final engines = _enginesFor(source);
    if (engines.isEmpty) throw LxJsException('没有脚本支持音源 $source');
    Object? lastError;
    for (final engine in engines) {
      try {
        return await engine.getMusicUrl(
          source: source,
          musicInfo: musicInfo,
          quality: quality,
        );
      } catch (e) {
        lastError = e;
        lxJsLog('音源 $source 取链失败，换下一个脚本: $e');
      }
    }
    throw lastError is LxJsException ? lastError : LxJsException('$lastError');
  }

  /// 取歌词：同样按顺序试，第一个返回非空文本的赢。
  Future<String> getLyric(
    String source,
    Map<String, dynamic> musicInfo,
  ) async {
    final engines = _enginesFor(source, action: 'lyric');
    if (engines.isEmpty) throw LxJsException('没有脚本支持音源 $source 的歌词');
    Object? lastError;
    for (final engine in engines) {
      try {
        final lyric = await engine.getLyric(
          source: source,
          musicInfo: musicInfo,
        );
        if (lyric.trim().isNotEmpty) return lyric;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw lastError is LxJsException ? lastError : LxJsException('$lastError');
    }
    return '';
  }

  /// 取封面：同样按顺序试，第一个返回非空地址的赢；都没有返回空串。
  Future<String> getPic(
    String source,
    Map<String, dynamic> musicInfo,
  ) async {
    for (final engine in _enginesFor(source, action: 'pic')) {
      try {
        final url = await engine.getPic(source: source, musicInfo: musicInfo);
        if (url.isNotEmpty) return url;
      } catch (e) {
        lxJsLog('音源 $source 取封面失败，换下一个脚本: $e');
      }
    }
    return '';
  }

  /// 歌曲自身音质 ∩ 脚本声明音质；脚本没声明就原样返回。
  List<String> qualitysOf(String source, List<String> own) {
    final declared = sources[source]?.qualitys ?? const [];
    if (declared.isEmpty) return own;
    final result = own.where(declared.contains).toList();
    return result.isEmpty ? own : result;
  }

  /// 支持该音源的引擎，按导入顺序。
  Iterable<LxJsEngine> _enginesFor(String source, {String? action}) sync* {
    for (final script in _scripts) {
      final info = script.sources[source];
      if (info == null) continue;
      if (action != null && !info.actions.contains(action)) continue;
      yield script.engine;
    }
  }

  Future<void> unload() async {
    final scripts = [..._scripts];
    _scripts.clear();
    failures.clear();
    for (final script in scripts) {
      await script.engine.dispose();
    }
  }
}

final LxJsSourceManager lxJsSources = LxJsSourceManager();

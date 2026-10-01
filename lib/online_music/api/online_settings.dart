// 在线音乐的本地设置：自定义源脚本（可多个）、默认音质、下载目录。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';

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
        final map = asMap(jsonDecode(await _file.readAsString()));
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

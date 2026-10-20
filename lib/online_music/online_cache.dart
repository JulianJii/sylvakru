// 在线音乐的播放缓存（仅桌面）：命中直接播本地文件，未命中边播边落盘，
// 超过上限时按最旧文件清理。
//
// 缓存只是加速手段：所有网络/文件异常只记日志，绝不影响播放与设置。

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/api/online_http.dart';
import 'package:sylvakru/online_music/api/online_models.dart';
import 'package:sylvakru/online_music/api/online_settings.dart';

class OnlineCache {
  /// 缓存目录的当前占用（字节），设置页直接绑。
  final ValueNotifier<int> usedBytes = ValueNotifier(0);

  /// 正在写入的 `.part` 对应的最终路径，扫描时不能当残留删掉。
  final Set<String> _writing = {};

  Dio? _dio;
  bool _started = false;

  bool get enabled => !isMobile;

  /// 用户没选目录就用应用支持目录下的默认位置。
  Directory get directory {
    final custom = onlineSettings.cacheDir.value.trim();
    return Directory(
      custom.isEmpty
          ? p.join(appSupportDir.path, 'online_music_cache')
          : custom,
    );
  }

  int get maxBytes => onlineSettings.cacheMaxMb.value * 1024 * 1024;

  /// 缓存文件名：key 与直链缓存同口径，扩展名跟着音质走。
  static String cacheFileName(String source, String songmid, String quality) {
    final hash = md5.convert(utf8.encode('$source|$songmid|$quality'));
    return '$hash.${qualityExtension(quality)}';
  }

  static String _fileNameOf(OnlineTrack track, String quality) =>
      cacheFileName(track.source, track.songmid, quality);

  /// 命中缓存就返回文件；顺手把修改时间推到最新（清理按修改时间从旧到新）。
  File? lookup(OnlineTrack track, String quality) {
    if (!enabled) return null;
    final file = File(p.join(directory.path, _fileNameOf(track, quality)));
    if (!file.existsSync() || file.lengthSync() == 0) return null;
    try {
      file.setLastModifiedSync(DateTime.now());
    } catch (_) {}
    return file;
  }

  /// 启动时统计一次占用，顺手清掉上次退出留下的 `.part` 残骸。
  Future<void> init() async {
    if (_started || !enabled) return;
    _started = true;
    await refreshUsage();
    await enforceLimit();
  }

  /// 后台把直链写入缓存。同一首已在写就跳过，播放链路不等它。
  Future<void> store(OnlineTrack track, String quality, String url) async {
    if (!enabled) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    final target = p.join(directory.path, _fileNameOf(track, quality));
    if (File(target).existsSync() || !_writing.add(target)) return;
    final part = '$target.part';
    try {
      await directory.create(recursive: true);
      await (_dio ??= Dio()).download(
        url,
        part,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
      );
      final file = File(part);
      if (!await file.exists() || await file.length() == 0) return;
      await file.rename(target);
      await refreshUsage();
      await enforceLimit();
    } catch (e) {
      logger.output('[online] 缓存写入失败: $e');
      try {
        final file = File(part);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    } finally {
      _writing.remove(target);
    }
  }

  /// 统计当前目录占用；不在写入中的 `.part` 视为残骸直接删掉。
  Future<void> refreshUsage() async {
    if (!enabled) return;
    usedBytes.value = await _scan(directory);
  }

  /// 超过上限就按修改时间从旧到新删，删到不超为止。
  Future<void> enforceLimit() async {
    if (!enabled) return;
    usedBytes.value = await enforceLimitIn(directory, maxBytes);
  }

  /// 清空缓存。被播放器占用的文件删不掉（Windows 会抛），忽略即可。
  Future<void> clear() async {
    if (!enabled) return;
    await clearIn(directory);
    usedBytes.value = 0;
  }

  @visibleForTesting
  static Future<int> enforceLimitIn(Directory dir, int limit) async {
    if (!await dir.exists()) return 0;
    final files = <({File file, int size, DateTime modified})>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File || entity.path.endsWith('.part')) continue;
      try {
        final stat = await entity.stat();
        files.add((file: entity, size: stat.size, modified: stat.modified));
        total += stat.size;
      } catch (_) {}
    }
    if (total <= limit) return total;
    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final item in files) {
      if (total <= limit) break;
      try {
        await item.file.delete();
        total -= item.size;
      } catch (_) {}
    }
    return total < 0 ? 0 : total;
  }

  @visibleForTesting
  static Future<void> clearIn(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  Future<int> _scan(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        if (entity.path.endsWith('.part')) {
          final target = entity.path.substring(0, entity.path.length - 5);
          if (!_writing.contains(target)) await entity.delete();
          continue;
        }
        total += await entity.length();
      } catch (_) {}
    }
    return total;
  }
}

final OnlineCache onlineCache = OnlineCache();

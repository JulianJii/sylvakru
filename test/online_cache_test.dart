import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/online_music/online_cache.dart';

void main() {
  test('缓存文件名跟着音质走且同曲同档稳定', () {
    final a = OnlineCache.cacheFileName('kw', 'mid1', '320k');
    expect(a, OnlineCache.cacheFileName('kw', 'mid1', '320k'));
    expect(a, endsWith('.mp3'));
    expect(OnlineCache.cacheFileName('kw', 'mid1', 'flac'), endsWith('.flac'));
    expect(
      OnlineCache.cacheFileName('kw', 'mid1', 'flac24bit'),
      endsWith('.flac'),
    );
    expect(
      OnlineCache.cacheFileName('kw', 'mid1', 'master'),
      endsWith('.flac'),
    );
    // 音质不同就是不同缓存，不能拿 128k 的文件冒充 320k。
    expect(OnlineCache.cacheFileName('kw', 'mid1', 'flac'), isNot(a));
  });

  test('超过上限按最旧文件清理', () async {
    final dir = await Directory.systemTemp.createTemp('sylvakru_cache_test');
    addTearDown(() => dir.delete(recursive: true));

    Future<File> write(String name, DateTime modified) async {
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(List.filled(100, 0));
      await file.setLastModified(modified);
      return file;
    }

    final old = await write('old.mp3', DateTime(2020));
    final mid = await write('mid.mp3', DateTime(2021));
    final recent = await write('recent.mp3', DateTime(2022));

    final remaining = await OnlineCache.enforceLimitIn(dir, 250);
    expect(old.existsSync(), isFalse);
    expect(mid.existsSync(), isTrue);
    expect(recent.existsSync(), isTrue);
    expect(remaining, 200);
  });

  test('清空会连未完成的 .part 一起删掉', () async {
    final dir = await Directory.systemTemp.createTemp('sylvakru_cache_test');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/a.mp3').writeAsBytes([1, 2, 3]);
    await File('${dir.path}/b.mp3.part').writeAsBytes([1]);

    await OnlineCache.clearIn(dir);
    expect(dir.listSync().whereType<File>(), isEmpty);
  });
}

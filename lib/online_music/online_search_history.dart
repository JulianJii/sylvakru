import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sylvakru/base/services/logger.dart';

/// 在线音乐搜索历史记录管理类。
///
/// 使用 shared_preferences 本地持久化保存，通过 ValueNotifier 提供响应式通知。
class OnlineSearchHistory {
  static const String _storageKey = 'online_music_search_history';
  static const int maxHistory = 20;

  final ValueNotifier<List<String>> history = ValueNotifier(const []);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey) ?? const [];
      history.value = list;
    } catch (e) {
      logger.output('[online] 加载搜索历史失败: $e');
    }
  }

  Future<void> add(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    try {
      final current = List<String>.from(history.value);
      current.remove(trimmed);
      current.insert(0, trimmed);
      if (current.length > maxHistory) {
        current.removeRange(maxHistory, current.length);
      }
      history.value = current;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, current);
    } catch (e) {
      logger.output('[online] 保存搜索历史失败: $e');
    }
  }

  Future<void> remove(String keyword) async {
    try {
      final current = List<String>.from(history.value);
      if (current.remove(keyword)) {
        history.value = current;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_storageKey, current);
      }
    } catch (e) {
      logger.output('[online] 删除搜索历史失败: $e');
    }
  }

  Future<void> clear() async {
    try {
      history.value = const [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      logger.output('[online] 清空搜索历史失败: $e');
    }
  }
}

final OnlineSearchHistory onlineSearchHistory = OnlineSearchHistory();

// 在线音乐的设置对话框：左侧分类，右侧内容。
//
// 音源脚本的导入/移除/切换逻辑都在这里；缓存只占桌面端一块，移动端整块隐藏。

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';
import 'package:sylvakru/online_music/online_cache.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/theme/online_theme.dart';
import 'package:sylvakru/online_music/widgets/online_notice.dart';
import 'package:sylvakru/online_music/widgets/online_page_widgets.dart';

enum _SettingsSection { source, download, cache }

/// 在线音乐设置：音源脚本、下载与音质、播放缓存（仅桌面）。
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  _SettingsSection _section = _SettingsSection.source;
  bool _importing = false;
  bool _clearing = false;

  /// 已导入脚本声明了哪些音源，导入/移除后重建。
  late Future<Map<String, List<String>>> _sourcesFuture;

  @override
  void initState() {
    super.initState();
    _sourcesFuture = _refreshSources();
  }

  /// 一个脚本都没有就别去跑引擎了，否则这个 future 的异常没人接。
  Future<Map<String, List<String>>> _refreshSources() =>
      onlineSettings.hasScript
      ? onlineApiClient.fetchSources()
      : Future.value(const <String, List<String>>{});

  /// 填入脚本链接，下载正文后追加进列表并重新加载。同链接会替换原条目。
  Future<void> _importScript() async {
    if (_importing) return;
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const ScriptUrlDialog(),
    );
    if (url == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final script = await onlineApiClient.fetchScript(url);
      await onlineSettings.addScript(
        // 名字取脚本头注释里的 `@name`，链接末段只做兜底。
        LxScriptEntry.fromScript(
          script,
          name: _scriptNameFromUrl(url),
          url: url,
        ),
      );
      await onlineApiClient.reload();
      if (!mounted) return;
      // 箭头函数会把赋值结果（Future）当返回值，setState 会直接报错。
      setState(() {
        _sourcesFuture = _refreshSources();
      });
    } catch (e) {
      logger.output('[online] 导入脚本失败: $e');
      if (mounted) showOnlineNotice(context, '导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 脚本没写 `@name` 时的兜底名：链接末段（`xxx/lx-source.js` ->
  /// `lx-source.js`），没有末段就退回域名。
  String _scriptNameFromUrl(String url) {
    final uri = Uri.parse(url);
    return uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
  }

  /// 按列表位置移除。
  Future<void> _removeScript(int index) async {
    await onlineSettings.removeScript(index);
    await onlineApiClient.reload();
    if (!mounted) return;
    setState(() {
      _sourcesFuture = _refreshSources();
    });
  }

  /// 换一个生效的脚本：旧的引擎卸掉，重新加载新脚本并刷新那一行说明。
  Future<void> _selectScript(int index) async {
    if (index == onlineSettings.activeScriptIndex) return;
    await onlineSettings.setActiveScript(index);
    await onlineApiClient.reload();
    if (!mounted) return;
    setState(() {
      _sourcesFuture = _refreshSources();
    });
  }

  Future<void> _pickCacheDir() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;
    onlineSettings.cacheDir.value = path;
    await onlineSettings.save();
    await onlineCache.enforceLimit();
  }

  Future<void> _resetCacheDir() async {
    onlineSettings.cacheDir.value = '';
    await onlineSettings.save();
    await onlineCache.enforceLimit();
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await onlineCache.clear();
      if (mounted) showOnlineNotice(context, '缓存已清空');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = <(_SettingsSection, IconData, String)>[
      (_SettingsSection.source, Icons.javascript_rounded, '音源设置'),
      (_SettingsSection.download, Icons.download_rounded, '下载与音质'),
      if (onlineCache.enabled)
        (_SettingsSection.cache, Icons.storage_rounded, '缓存'),
    ];
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 808
        ? (size.width - 32).clamp(280.0, 760.0)
        : 760.0;
    final height = size.height < 660
        ? (size.height - 32).clamp(320.0, 620.0)
        : 620.0;

    return Dialog(
      // 底色 / 圆角 / 标题字号由 buildOnlineTheme 统一给出。
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
              child: Row(
                children: [
                  const Text('设置', style: OnlineText.dialogTitle),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: OnlinePalette.cardBorder),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 560;
                  final content = Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      // 默认 layoutBuilder 用 Stack 包裹，会让内容在垂直方向居中
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.topLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey(_section),
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                        child: switch (_section) {
                          _SettingsSection.source => _buildSourceSection(),
                          _SettingsSection.download => _buildDownloadSection(),
                          _SettingsSection.cache => _buildCacheSection(),
                        },
                      ),
                    ),
                  );
                  if (compact) {
                    return Column(
                      children: [
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              for (final item in sections)
                                _SectionTab(
                                  icon: item.$2,
                                  label: item.$3,
                                  selected: _section == item.$1,
                                  compact: true,
                                  onTap: () =>
                                      setState(() => _section = item.$1),
                                ),
                            ],
                          ),
                        ),
                        content,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(
                        width: 168,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          children: [
                            for (final item in sections)
                              _SectionTab(
                                icon: item.$2,
                                label: item.$3,
                                selected: _section == item.$1,
                                compact: false,
                                onTap: () => setState(() => _section = item.$1),
                              ),
                          ],
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: OnlinePalette.cardBorder,
                      ),
                      content,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 音源设置

  Widget _buildSourceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '播放直链由洛雪音乐的「自定义源」脚本解析，可导入多个 .js 脚本链接；'
          '音源单选，只有勾选的那个脚本生效。',
          style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
        ),
        const SizedBox(height: 16),
        _buildScriptArea(),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: OnlinePalette.primary,
            foregroundColor: OnlinePalette.onPrimary,
          ),
          onPressed: _importing ? null : _importScript,
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('导入脚本'),
        ),
      ],
    );
  }

  /// 列出已导入的脚本与它们声明的音源。脚本声明在加载后才拿得到，
  /// 所以顺手触发一次加载。
  Widget _buildScriptArea() {
    return ListenableBuilder(
      // 选中状态也是这个列表的一部分，两个 notifier 都要听。
      listenable: Listenable.merge([
        onlineSettings.scripts,
        onlineSettings.activeScript,
      ]),
      builder: (context, _) {
        final scripts = onlineSettings.scripts.value;
        if (scripts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '还没有自定义源脚本，请填入脚本链接导入',
              style: TextStyle(color: OnlinePalette.textFaint),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<int>(
              groupValue: onlineSettings.activeScriptIndex,
              onChanged: (index) {
                if (index != null) _selectScript(index);
              },
              child: Column(
                children: [
                  for (var index = 0; index < scripts.length; index++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: index == scripts.length - 1 ? 0 : 6,
                      ),
                      child: _buildScriptTile(scripts[index], index),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, List<String>>>(
              future: _sourcesFuture,
              builder: (context, snapshot) => Text(
                _sourcesText(snapshot),
                style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScriptTile(LxScriptEntry entry, int index) {
    final active = index == onlineSettings.activeScriptIndex;
    // 用 Material 而不是带底色的 Container：ListTile 的水波纹画在最近的
    // Material 上，夹一层 DecoratedBox 会被它盖住（框架会直接报断言）。
    return Material(
      color: OnlinePalette.surfaceAlt,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: active ? OnlinePalette.primary : Colors.transparent,
        ),
      ),
      child: ListTile(
        dense: true,
        onTap: active ? null : () => _selectScript(index),
        leading: const Icon(Icons.javascript_rounded, size: 18),
        title: Text(
          '${index + 1}. ${entry.name}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: entry.url.isEmpty
            ? null
            : Text(
                entry.url,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: OnlinePalette.textFaint),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radio<int>(value: index),
            IconButton(
              tooltip: '移除',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => _removeScript(index),
            ),
          ],
        ),
      ),
    );
  }

  /// 「已声明音源 / 哪个脚本挂了」那一行。
  String _sourcesText(AsyncSnapshot<Map<String, List<String>>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return '正在加载脚本…';
    if (snapshot.hasError) return '脚本加载失败：${snapshot.error}';
    final sources = snapshot.data ?? const {};
    final failures = lxJsSources.failures;
    if (sources.isEmpty && failures.isEmpty) return '脚本没有声明可用的音源';
    return [
      if (sources.isNotEmpty) '已声明音源：${sources.keys.join('、')}',
      ...failures,
    ].join('\n');
  }

  // ------------------------------------------------------------ 下载与音质

  Widget _buildDownloadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                '下载目录',
                style: TextStyle(fontSize: 13, color: OnlinePalette.textDim),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: onlineSettings.downloadDir,
                builder: (context, _, _) => Text(
                  onlineDownloader.directoryDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: OnlinePalette.textFaint,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => onlineDownloader.pickDirectory(),
              child: const Text('选择'),
            ),
          ],
        ),
        Divider(height: 24, color: OnlinePalette.surfaceAlt),
        Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                '默认音质',
                style: TextStyle(fontSize: 13, color: OnlinePalette.textDim),
              ),
            ),
            QualityMenu(
              valueListenable: onlineSettings.quality,
              onSelected: (value) {
                onlineSettings.quality.value = value;
                onlineSettings.save();
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '下载目录用于「下载」按钮保存歌曲；默认音质同时用于播放与下载。',
          style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 缓存

  Widget _buildCacheSection() {
    return ValueListenableBuilder<String>(
      valueListenable: onlineSettings.cacheDir,
      builder: (context, customDir, _) {
        final dir = customDir.trim().isEmpty
            ? onlineCache.directory.path
            : customDir;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '播放时把音频缓存到本地，下次播放直接读缓存，省掉解析直链与网络缓冲。',
              style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    '缓存目录',
                    style: TextStyle(
                      fontSize: 13,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    dir,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                ),
                TextButton(onPressed: _pickCacheDir, child: const Text('选择')),
                if (customDir.trim().isNotEmpty)
                  TextButton(
                    onPressed: _resetCacheDir,
                    child: const Text('默认'),
                  ),
              ],
            ),
            Divider(height: 24, color: OnlinePalette.surfaceAlt),
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    '缓存上限',
                    style: TextStyle(
                      fontSize: 13,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                ),
                const _CacheLimitMenu(),
                const SizedBox(width: 12),
                ValueListenableBuilder<int>(
                  valueListenable: onlineCache.usedBytes,
                  builder: (context, bytes, _) => Text(
                    '已占用 ${_formatBytes(bytes)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: OnlinePalette.danger,
                  side: BorderSide(color: OnlinePalette.danger.withAlpha(120)),
                ),
                onPressed: _clearing ? null : _clearCache,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('清空缓存'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '缓存仅用于加速播放，清空不影响已下载的歌曲。',
              style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ 小部件

/// 左侧/顶部的一个分类入口。
class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 0,
        vertical: compact ? 6 : 2,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 8 : 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? OnlinePalette.primary.withAlpha(24)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: selected ? OnlinePalette.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Icon(
                icon,
                size: 17,
                color: selected
                    ? OnlinePalette.primaryLight
                    : OnlinePalette.textFaint,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? OnlinePalette.text : OnlinePalette.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缓存上限的档位菜单。
class _CacheLimitMenu extends StatelessWidget {
  const _CacheLimitMenu();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: onlineSettings.cacheMaxMb,
      builder: (context, value, _) {
        return PopupMenuButton<int>(
          tooltip: '缓存上限',
          initialValue: value,
          color: OnlinePalette.surfaceAlt,
          onSelected: (limit) async {
            onlineSettings.cacheMaxMb.value = limit;
            await onlineSettings.save();
            await onlineCache.enforceLimit();
          },
          itemBuilder: (context) => [
            for (final limit in OnlineSettings.cacheMaxOptions)
              PopupMenuItem<int>(
                value: limit,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: limit == value
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: OnlinePalette.primaryLight,
                            )
                          : null,
                    ),
                    Text(_limitLabel(limit)),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: OnlinePalette.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sd_storage_rounded,
                  size: 16,
                  color: OnlinePalette.textDim,
                ),
                const SizedBox(width: 6),
                Text(_limitLabel(value), style: const TextStyle(fontSize: 13)),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: OnlinePalette.textDim,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _limitLabel(int mb) => mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

String _formatBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(2)} GB'
      : '${mb.toStringAsFixed(1)} MB';
}

/// 输入自定义源脚本的下载链接。
class ScriptUrlDialog extends StatefulWidget {
  const ScriptUrlDialog({super.key});

  @override
  State<ScriptUrlDialog> createState() => _ScriptUrlDialogState();
}

class _ScriptUrlDialogState extends State<ScriptUrlDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入自定义源脚本'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          hintText: 'https://example.com/lx-source.js',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('导入')),
      ],
    );
  }
}

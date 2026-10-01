// 音源设置对话框与导入脚本链接的对话框。

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/theme/online_theme.dart';
import 'package:sylvakru/online_music/widgets/online_notice.dart';
import 'package:sylvakru/online_music/widgets/online_page_widgets.dart';

/// 音源设置：管理自定义源脚本、下载目录与默认音质。
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _importing = false;

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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: OnlinePalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '音源设置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '播放直链由洛雪音乐的「自定义源」脚本解析，可导入多个 .js 脚本链接；'
                '音源单选，只有勾选的那个脚本生效。',
                style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
              ),
              const SizedBox(height: 14),
              Flexible(child: _buildScriptArea()),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: OnlinePalette.primary,
                  foregroundColor: OnlinePalette.onPrimary,
                ),
                onPressed: _importing ? null : _importScript,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('导入脚本'),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: OnlinePalette.surfaceAlt),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '下载目录',
                    style: TextStyle(
                      fontSize: 13,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                  const SizedBox(width: 16),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '默认音质',
                    style: TextStyle(
                      fontSize: 13,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                  const SizedBox(width: 16),
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
            ],
          ),
        ),
      ),
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
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '还没有自定义源脚本，请填入脚本链接导入',
                style: TextStyle(color: OnlinePalette.textFaint),
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              // 单选组：一屏里的单选框归一组，点哪个哪个生效。
              child: RadioGroup<int>(
                groupValue: onlineSettings.activeScriptIndex,
                onChanged: (index) {
                  if (index != null) _selectScript(index);
                },
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: scripts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) =>
                      _buildScriptTile(scripts[index], index),
                ),
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
      backgroundColor: OnlinePalette.surface,
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

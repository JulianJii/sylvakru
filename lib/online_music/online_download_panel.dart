// 下载管理面板：查看/控制在线音乐的下载任务，以及选择、打开下载目录。

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/theme/online_theme.dart';
import 'package:sylvakru/online_music/widgets/online_page_widgets.dart';

/// 以对话框形式打开下载管理面板。
Future<void> openDownloadPanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _DownloadPanel(),
  );
}

class _DownloadPanel extends StatelessWidget {
  const _DownloadPanel();

  @override
  Widget build(BuildContext context) {
    // 底色 / 圆角 / 标题字号都由 buildOnlineTheme 统一给出。
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('下载管理', style: OnlineText.dialogTitle),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const _DirectoryBar(),
              const SizedBox(height: 8),
              Divider(height: 1, color: OnlinePalette.cardBorder),
              const SizedBox(height: 4),
              Flexible(child: _buildList()),
              const SizedBox(height: 8),
              const _Footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ValueListenableBuilder<List<OnlineDownloadEntry>>(
      valueListenable: onlineDownloader.entries,
      builder: (context, entries, _) {
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: OnlinePalette.surfaceAlt,
                    borderRadius: BorderRadius.circular(
                      OnlineLayout.radiusCard,
                    ),
                  ),
                  child: Icon(
                    Icons.download_done_rounded,
                    size: 26,
                    color: OnlinePalette.textFaint,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '还没有下载任务',
                  style: OnlineText.body.copyWith(color: OnlinePalette.textDim),
                ),
                const SizedBox(height: 6),
                Text(
                  '点搜索结果右侧的下载按钮即可保存到下载目录',
                  textAlign: TextAlign.center,
                  style: OnlineText.caption.copyWith(
                    color: OnlinePalette.textFaint,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: entries.length,
          itemBuilder: (context, index) =>
              _EntryRow(entry: entries[entries.length - 1 - index]),
        );
      },
    );
  }
}

class _DirectoryBar extends StatelessWidget {
  const _DirectoryBar();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: onlineSettings.downloadDir,
      builder: (context, dir, _) {
        return Row(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 16,
              color: OnlinePalette.textFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                onlineDownloader.directoryDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OnlineText.caption.copyWith(
                  color: OnlinePalette.textDim,
                ),
              ),
            ),
            TextButton(
              onPressed: () => onlineDownloader.pickDirectory(),
              child: Text(dir.isEmpty ? '选择目录' : '更改'),
            ),
          ],
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        onlineDownloader.entries,
        onlineSettings.downloadDir,
      ]),
      builder: (context, _) {
        final entries = onlineDownloader.entries.value;
        final hasFinished = entries.any((entry) => !entry.state.isActive);
        return Row(
          children: [
            TextButton.icon(
              // iOS 的书签还原不出路径，这种时候干脆不给点。
              onPressed: onlineDownloader.canOpenDirectory
                  ? () => onlineDownloader.openDirectory()
                  : null,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('打开目录'),
            ),
            const Spacer(),
            if (hasFinished)
              TextButton.icon(
                onPressed: onlineDownloader.clearFinished,
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: const Text('清空已完成'),
              ),
          ],
        );
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final OnlineDownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final active = entry.state.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: OnlinePalette.surfaceAlt,
          borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnlineText.body.copyWith(color: OnlinePalette.text),
                  ),
                ),
                const SizedBox(width: 8),
                OnlineTag(text: entry.quality),
                const SizedBox(width: 4),
                // 结束的条目不需要暂停键，删除键已在下面一行。
                if (active) _PauseButton(entry: entry),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _stateText(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnlineText.caption.copyWith(
                      color: entry.state == OnlineDownloadState.failed
                          ? OnlinePalette.danger
                          : OnlinePalette.textFaint,
                    ),
                  ),
                ),
                if (active)
                  IconButton(
                    tooltip: '取消',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onlineDownloader.cancel(entry.trackId),
                    icon: Icon(
                      Icons.close_rounded,
                      color: OnlinePalette.textFaint,
                    ),
                  )
                else
                  IconButton(
                    tooltip: '从列表移除',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onlineDownloader.remove(entry.trackId),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: entry.progress <= 0 ? null : entry.progress,
                  minHeight: 3,
                  color: OnlinePalette.primaryLight,
                  backgroundColor: OnlinePalette.surface,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.entry});

  final OnlineDownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final paused = entry.state == OnlineDownloadState.paused;
    return IconButton(
      tooltip: paused ? '继续' : '暂停',
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      // Uri 下载在部分平台不支持暂停；失败就保持原状，不打断用户。
      onPressed: () => paused
          ? onlineDownloader.resume(entry.trackId)
          : onlineDownloader.pause(entry.trackId),
      icon: Icon(
        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        color: OnlinePalette.textFaint,
      ),
    );
  }
}

String _stateText(OnlineDownloadEntry entry) => switch (entry.state) {
  .resolving => '正在解析直链…',
  .enqueued => '排队中',
  .running => '下载中 ${(entry.progress * 100).round()}%',
  .paused => '已暂停',
  .complete => '已完成',
  .failed => '失败：${entry.error ?? '未知原因'}',
  .canceled => '已取消',
};

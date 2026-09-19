// 下载管理面板：查看/控制在线音乐的下载任务，以及选择、打开下载目录。

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/online_music_page.dart';

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
    return Dialog(
      backgroundColor: OnlinePalette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    '下载管理',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const _DirectoryBar(),
              const SizedBox(height: 12),
              Divider(height: 1, color: OnlinePalette.surfaceAlt),
              const SizedBox(height: 8),
              Flexible(child: _buildList()),
              const SizedBox(height: 12),
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
                Icon(
                  Icons.download_done_rounded,
                  size: 40,
                  color: OnlinePalette.textFaint,
                ),
                SizedBox(height: 12),
                Text('还没有下载任务', style: TextStyle(color: OnlinePalette.textDim)),
                SizedBox(height: 6),
                Text(
                  '点搜索结果右侧的下载按钮即可保存到下载目录',
                  style: TextStyle(
                    fontSize: 12,
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
                style: TextStyle(fontSize: 12, color: OnlinePalette.textDim),
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
              onPressed: onlineDownloader.hasDirectory
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: OnlinePalette.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
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
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                _Tag(text: entry.quality),
                const SizedBox(width: 6),
                // 结束的条目不需要暂停键，删除键已在下面一行。
                if (active) _PauseButton(entry: entry),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _stateText(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
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
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: entry.progress <= 0 ? null : entry.progress,
                minHeight: 3,
                color: OnlinePalette.primaryLight,
                backgroundColor: OnlinePalette.surface.withAlpha(120),
              ),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: OnlinePalette.textFaint.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: OnlinePalette.textFaint),
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

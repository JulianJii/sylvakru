// 在线音乐页的叶子组件：搜索区的下拉、结果列表行、封面、下载相关按钮等。
//
// 从 online_music_page.dart 抽出来，页面只负责组装与弹窗调度。

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/online_music/online_download.dart';
import 'package:sylvakru/online_music/online_download_panel.dart';
import 'package:sylvakru/online_music/online_music_api.dart';
import 'package:sylvakru/online_music/theme/online_theme.dart';

/// 小圆角标签。不给 [color] 时用次级前景色。
class OnlineTag extends StatelessWidget {
  const OnlineTag({required this.text, this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? OnlinePalette.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: foreground)),
    );
  }
}

/// 音源单选下拉。样式与 [QualityMenu] 保持一致，选中即回调。
/// [allowed] 之外的源不显示（脚本没声明的源搜到也播不了）。
class SourceFilterSelect extends StatelessWidget {
  const SourceFilterSelect({
    required this.value,
    required this.allowed,
    required this.onChanged,
    super.key,
  });

  final String value;
  final List<String> allowed;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = <String, String>{
      for (final source in allowed)
        source: onlineSearchers[source]?.label ?? source,
    };
    return PopupMenuButton<String>(
      tooltip: '音源',
      initialValue: value,
      onSelected: onChanged,
      color: OnlinePalette.surfaceAlt,
      itemBuilder: (context) => [
        for (final entry in entries.entries)
          PopupMenuItem<String>(
            value: entry.key,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: entry.key == value
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: OnlinePalette.primaryLight,
                        )
                      : null,
                ),
                Text(entry.value),
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
              Icons.library_music_rounded,
              size: 16,
              color: OnlinePalette.textDim,
            ),
            const SizedBox(width: 6),
            Text(entries[value] ?? value, style: const TextStyle(fontSize: 13)),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: OnlinePalette.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

class QualityMenu extends StatelessWidget {
  const QualityMenu({
    required this.valueListenable,
    required this.onSelected,
    super.key,
  });

  final ValueListenable<String> valueListenable;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: valueListenable,
      builder: (context, quality, _) {
        return PopupMenuButton<String>(
          tooltip: '音质',
          initialValue: quality,
          onSelected: onSelected,
          color: OnlinePalette.surfaceAlt,
          itemBuilder: (context) => [
            for (final item in qualityOrder)
              PopupMenuItem<String>(
                value: item,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: item == quality
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: OnlinePalette.primaryLight,
                            )
                          : null,
                    ),
                    Text(item),
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
                  Icons.high_quality_rounded,
                  size: 16,
                  color: OnlinePalette.textDim,
                ),
                const SizedBox(width: 6),
                Text(quality, style: const TextStyle(fontSize: 13)),
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

/// 所有内置音源名（"酷我 / 酷狗 / …"），空状态提示用。
String get _sourceLabels =>
    onlineSearchers.values.map((searcher) => searcher.label).join(' / ');

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.searching,
    this.isPlaylist = false,
    this.hint,
    super.key,
  });

  final bool searching;
  final bool isPlaylist;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: searching
            ? Column(
                key: ValueKey('loading'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: OnlinePalette.primaryLight,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '正在搜索…',
                    style: TextStyle(color: OnlinePalette.textFaint),
                  ),
                ],
              )
            : Column(
                key: ValueKey(isPlaylist ? 'idle_playlist' : 'idle_song'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPlaylist
                        ? Icons.queue_music_rounded
                        : Icons.travel_explore_rounded,
                    size: 46,
                    color: OnlinePalette.textFaint,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isPlaylist ? '输入关键词搜索歌单' : '输入关键词开始搜索',
                    style: TextStyle(
                      fontSize: 15,
                      color: OnlinePalette.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isPlaylist
                        ? '搜索结果来自$_sourceLabels的歌单，点击歌单可查看曲目并播放'
                        : '搜索结果来自$_sourceLabels，播放直链由自定义源脚本解析',
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      hint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: OnlinePalette.warn,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// 列表末尾的页脚：还有下一页就挂载时的转圈（点一下可以手动再拉一次），
/// 翻到底了就一行"没有更多了"。
class ListFooter extends StatelessWidget {
  const ListFooter({required this.hasMore, required this.onLoadMore, super.key});

  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onLoadMore,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: OnlinePalette.primaryLight,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '正在加载更多…',
                style: TextStyle(fontSize: 12, color: OnlinePalette.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryChip extends StatelessWidget {
  const HistoryChip({
    required this.label,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: OnlinePalette.surfaceAlt,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: OnlinePalette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: OnlinePalette.surfaceAlt),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: OnlinePalette.textDim),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(10),
              hoverColor: OnlinePalette.text.withAlpha(20),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: OnlinePalette.textFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TypeOption extends StatelessWidget {
  const TypeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? OnlinePalette.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? OnlinePalette.onPrimary
                  : OnlinePalette.textFaint,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? OnlinePalette.onPrimary
                    : OnlinePalette.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistRow extends StatelessWidget {
  const PlaylistRow({
    required this.index,
    required this.playlist,
    required this.onTap,
    super.key,
  });

  final int index;
  final OnlinePlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: OnlinePalette.surfaceAlt,
          child: Container(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 10, 16, 10),
            decoration: BoxDecoration(
              color: OnlinePalette.surface.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: OnlinePalette.surfaceAlt.withAlpha(80)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlinePalette.textFaint,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: playlist.pic.isNotEmpty
                        ? Image.network(
                            playlist.pic,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: OnlinePalette.surfaceAlt,
                              child: Icon(
                                Icons.queue_music_rounded,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          )
                        : Container(
                            color: OnlinePalette.surfaceAlt,
                            child: Icon(
                              Icons.queue_music_rounded,
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: OnlinePalette.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              playlist.creator.isEmpty
                                  ? '未知作者'
                                  : playlist.creator,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            playlist.songCountFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                          if (!compact &&
                              playlist.playCountFormatted.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              playlist.playCountFormatted,
                              style: TextStyle(
                                fontSize: 12,
                                color: OnlinePalette.textFaint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OnlineTag(
                  text:
                      onlineSearchers[playlist.source]?.label ??
                      playlist.source,
                  color: OnlinePalette.primaryLight,
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: OnlinePalette.textFaint,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 在线曲目封面。搜索结果里酷我不带封面、咪咕也可能缺，所以这里按 lx-music
/// 的 getPic 口径现取一次（脚本 `pic` action -> 音源接口）。结果由
/// [onlineApiClient] 缓存并去重，同一首歌在多处显示只会请求一次。
class OnlineCover extends StatefulWidget {
  const OnlineCover({
    required this.track,
    this.placeholder,
    this.fit = BoxFit.cover,
    super.key,
  });

  /// 要显示封面的曲目；null 表示当前没有在线曲目，直接显示占位图。
  final OnlineTrack? track;

  /// 没有封面或加载失败时显示什么，不给就什么都不显示。
  final Widget? placeholder;

  final BoxFit fit;

  @override
  State<OnlineCover> createState() => _OnlineCoverState();
}

class _OnlineCoverState extends State<OnlineCover> {
  String _url = '';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant OnlineCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id) {
      _url = '';
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final track = widget.track;
    if (track == null) return;
    final url = await onlineApiClient.fetchPicUrl(track);
    if (!mounted || url.isEmpty || track.id != widget.track?.id) return;
    setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final url = _url.isNotEmpty ? _url : widget.track?.img ?? '';
    if (url.isEmpty) return widget.placeholder ?? const SizedBox.shrink();
    return Image.network(
      url,
      fit: widget.fit,
      errorBuilder: (_, _, _) => widget.placeholder ?? const SizedBox.shrink(),
    );
  }
}

class TrackRow extends StatelessWidget {
  const TrackRow({
    required this.index,
    required this.track,
    required this.qualityLabel,
    required this.isCurrent,
    required this.isResolving,
    required this.onTap,
    required this.onDownload,
    super.key,
  });

  final int index;
  final OnlineTrack track;
  final String qualityLabel;
  final bool isCurrent;
  final bool isResolving;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: OnlinePalette.surfaceAlt,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 10, 16, 10),
            decoration: BoxDecoration(
              color: isCurrent
                  ? OnlinePalette.primary.withAlpha(30)
                  : OnlinePalette.surface.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCurrent
                    ? OnlinePalette.primary.withAlpha(120)
                    : OnlinePalette.surfaceAlt.withAlpha(80),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: isResolving
                      // Center 给宽松约束：否则外层 SizedBox(32) 的紧宽度会把
                      // 转圈压成 32x16 的扁圆。
                      ? Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: OnlinePalette.primaryLight,
                            ),
                          ),
                        )
                      : isCurrent
                      ? Icon(
                          Icons.equalizer_rounded,
                          size: 18,
                          color: OnlinePalette.primaryLight,
                        )
                      : Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 12,
                            color: OnlinePalette.textFaint,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: OnlineCover(
                      track: track,
                      placeholder: Container(
                        color: OnlinePalette.surfaceAlt,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 18,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isCurrent
                              ? OnlinePalette.primaryLight
                              : OnlinePalette.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        compact
                            ? track.singer
                            : '${track.singer} · ${track.albumName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  OnlineTag(text: qualityLabel, color: OnlinePalette.textFaint),
                  const SizedBox(width: 6),
                  OnlineTag(
                    text: onlineSearchers[track.source]?.label ?? track.source,
                    color: OnlinePalette.primaryLight,
                  ),
                ],
                const SizedBox(width: 10),
                Text(
                  track.interval,
                  style: TextStyle(
                    fontSize: 12,
                    color: OnlinePalette.textFaint,
                  ),
                ),
                const SizedBox(width: 4),
                DownloadButton(track: track, onDownload: onDownload),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 行内下载按钮。只订阅自己的曲目，进度刷新不会重建整行。
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    required this.track,
    required this.onDownload,
    super.key,
  });

  final OnlineTrack track;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<OnlineDownloadEntry>>(
      valueListenable: onlineDownloader.entries,
      builder: (context, _, _) {
        final entry = onlineDownloader.entryOf(track.id);
        final state = entry?.state;
        final done = state == OnlineDownloadState.complete;
        final active = state?.isActive ?? false;
        return IconButton(
          tooltip: '下载到下载目录',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: active ? null : onDownload,
          icon: done
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: OnlinePalette.success,
                )
              : active
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: entry!.progress > 0 ? entry.progress : null,
                    color: OnlinePalette.primaryLight,
                  ),
                )
              : Icon(Icons.download_rounded, color: OnlinePalette.textFaint),
        );
      },
    );
  }
}

/// 工具栏上的下载管理入口，右上角挂进行中的任务数。
class DownloadIndicator extends StatelessWidget {
  const DownloadIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<OnlineDownloadEntry>>(
      valueListenable: onlineDownloader.entries,
      builder: (context, entries, _) {
        final count = entries.where((entry) => entry.state.isActive).length;
        return Badge(
          label: Text('$count'),
          isLabelVisible: count > 0,
          backgroundColor: OnlinePalette.primary,
          textColor: OnlinePalette.onPrimary,
          child: IconButton(
            tooltip: '下载管理',
            onPressed: () => openDownloadPanel(context),
            icon: const Icon(Icons.download_rounded),
          ),
        );
      },
    );
  }
}

/// 音量按钮：点开后用 [MenuAnchor] 弹一条音量滑块。
///
/// 不用 PopupMenuButton —— 它点哪都关菜单，滑块拖不动。
class VolumeButton extends StatelessWidget {
  const VolumeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: volumeNotifier,
      builder: (context, volume, _) {
        return MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(OnlinePalette.surfaceAlt),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            elevation: WidgetStatePropertyAll(6),
          ),
          menuChildren: [
            SizedBox(
              width: 200,
              height: 44,
              child: Row(
                children: [
                  Icon(
                    _iconFor(volume),
                    size: 18,
                    color: OnlinePalette.textDim,
                  ),
                  Expanded(
                    child: Slider(
                      value: volume.clamp(0.0, 1.0),
                      onChanged: (value) {
                        volumeNotifier.value = value;
                        audioHandler.setVolume(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          builder: (context, controller, child) {
            return IconButton(
              tooltip: '音量',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: Icon(_iconFor(volume)),
            );
          },
        );
      },
    );
  }

  IconData _iconFor(double volume) {
    if (volume <= 0) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }
}

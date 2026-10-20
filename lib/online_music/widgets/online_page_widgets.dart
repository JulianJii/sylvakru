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
///
/// 只占单行：标签跟着行里剩余宽度走，宿主容器宽度不够时省略而不是撑破行。
class OnlineTag extends StatelessWidget {
  const OnlineTag({required this.text, this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? OnlinePalette.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withAlpha(24),
        borderRadius: BorderRadius.circular(OnlineLayout.radiusTag),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: OnlineText.tag.copyWith(color: foreground),
      ),
    );
  }
}

/// 音源单选下拉。[allowed] 之外的源不显示（脚本没声明的源搜到也播不了）。
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
    return _FilterMenu(
      tooltip: '音源',
      icon: Icons.library_music_rounded,
      value: value,
      entries: {
        for (final source in allowed)
          source: onlineSearchers[source]?.label ?? source,
      },
      onSelected: onChanged,
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
      builder: (context, quality, _) => _FilterMenu(
        tooltip: '音质',
        icon: Icons.high_quality_rounded,
        value: quality,
        entries: {for (final item in qualityOrder) item: item},
        onSelected: onSelected,
      ),
    );
  }
}

/// 音源 / 音质共用的下拉外观：图标 + 当前值 + 展开箭头，菜单里勾选当前项。
///
/// 两个入口只是数据不同，之前各抄了一份完全一样的样式，改一次要改两处。
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.entries,
    required this.onSelected,
  });

  final String tooltip;
  final IconData icon;
  final String value;
  final Map<String, String> entries;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      initialValue: value,
      onSelected: onSelected,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: OnlinePalette.surfaceAlt,
          borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: OnlinePalette.textDim),
            const SizedBox(width: 6),
            Text(
              entries[value] ?? value,
              style: OnlineText.body.copyWith(color: OnlinePalette.text),
            ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
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
                    const SizedBox(height: 16),
                    Text(
                      '正在搜索…',
                      style: OnlineText.body.copyWith(
                        color: OnlinePalette.textFaint,
                      ),
                    ),
                  ],
                )
              : ConstrainedBox(
                  key: ValueKey(isPlaylist ? 'idle_playlist' : 'idle_song'),
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: OnlinePalette.surfaceAlt,
                          borderRadius: BorderRadius.circular(
                            OnlineLayout.radiusCard,
                          ),
                        ),
                        child: Icon(
                          isPlaylist
                              ? Icons.queue_music_rounded
                              : Icons.travel_explore_rounded,
                          size: 30,
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isPlaylist ? '输入关键词搜索歌单' : '输入关键词开始搜索',
                        textAlign: TextAlign.center,
                        style: OnlineText.sectionTitle.copyWith(
                          color: OnlinePalette.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPlaylist
                            ? '搜索结果来自$_sourceLabels的歌单，点击歌单可查看曲目并播放'
                            : '搜索结果来自$_sourceLabels，播放直链由自定义源脚本解析',
                        textAlign: TextAlign.center,
                        style: OnlineText.caption.copyWith(
                          color: OnlinePalette.textFaint,
                          height: 1.5,
                        ),
                      ),
                      if (hint != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          hint!,
                          textAlign: TextAlign.center,
                          style: OnlineText.caption.copyWith(
                            color: OnlinePalette.warn,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// 列表末尾的页脚：还有下一页就挂载时的转圈（点一下可以手动再拉一次），
/// 翻到底了就一行"没有更多了"。
class ListFooter extends StatelessWidget {
  const ListFooter({
    required this.hasMore,
    required this.onLoadMore,
    super.key,
  });

  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            '没有更多了',
            style: OnlineText.caption.copyWith(color: OnlinePalette.textFaint),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onLoadMore,
      borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
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
                style: OnlineText.caption.copyWith(
                  color: OnlinePalette.textFaint,
                ),
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
    // 同样把 InkWell 放进透明 Material 里：底色画在外层 Container 上，
    // 水波纹/悬停色画在它上面，否则会被不透明底色整块盖住。
    return Container(
      decoration: BoxDecoration(
        color: OnlinePalette.card,
        borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
        border: Border.all(color: OnlinePalette.cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: OnlinePalette.hover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: OnlineText.caption.copyWith(
                    color: OnlinePalette.textDim,
                  ),
                ),
                const SizedBox(width: 2),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: OnlinePalette.text.withAlpha(24),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
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
      hoverColor: OnlinePalette.hover,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              style: OnlineText.body.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
        // 窄（手机单列）只留名称和作者；中/宽再补上播放量与音源标签。
        final width = constraints.maxWidth;
        final compact = width < 460;
        final roomy = width >= 480;
        return Container(
          decoration: BoxDecoration(
            color: OnlinePalette.card,
            borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
            border: Border.all(color: OnlinePalette.cardBorder),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              hoverColor: OnlinePalette.hover,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14,
                  10,
                  compact ? 8 : 14,
                  10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '$index',
                        style: OnlineText.caption.copyWith(
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: playlist.pic.isNotEmpty
                            ? Image.network(
                                playlist.pic,
                                fit: BoxFit.cover,
                                frameBuilder: fadeInFrame,
                                errorBuilder: (_, _, _) =>
                                    _playlistCoverPlaceholder(),
                              )
                            : _playlistCoverPlaceholder(),
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
                            style: OnlineText.title.copyWith(
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
                                  style: OnlineText.caption.copyWith(
                                    color: OnlinePalette.textFaint,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                playlist.songCountFormatted,
                                style: OnlineText.caption.copyWith(
                                  color: OnlinePalette.textFaint,
                                ),
                              ),
                              if (roomy &&
                                  playlist.playCountFormatted.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  playlist.playCountFormatted,
                                  style: OnlineText.caption.copyWith(
                                    color: OnlinePalette.textFaint,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      OnlineTag(
                        text:
                            onlineSearchers[playlist.source]?.label ??
                            playlist.source,
                        color: OnlinePalette.primaryLight,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                      Icons.chevron_right_rounded,
                      color: OnlinePalette.textFaint,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _playlistCoverPlaceholder() {
    return Container(
      color: OnlinePalette.surfaceAlt,
      child: Icon(
        Icons.queue_music_rounded,
        size: 22,
        color: OnlinePalette.textFaint,
      ),
    );
  }
}

/// 网络图片的淡入 builder：占位图直接换成图片会"啪"地一下，这里补 200ms 过渡。
Widget fadeInFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    child: child,
  );
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
      frameBuilder: fadeInFrame,
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
        // 三档：窄（手机单列）只留歌名/歌手，中档补音质，宽档再补音源。
        final width = constraints.maxWidth;
        final compact = width < 460;
        final roomy = width >= 480;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: isCurrent ? OnlinePalette.selected : OnlinePalette.card,
            borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
            border: Border.all(
              color: isCurrent
                  ? OnlinePalette.selectedBorder
                  : OnlinePalette.cardBorder,
            ),
          ),
          // 悬停/水波纹画在这层透明 Material 上：外层 AnimatedContainer 的
          // 底色是不透明的，直接套 InkWell 会被它整块盖住，hover 根本看不见。
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(OnlineLayout.radiusRow),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              hoverColor: OnlinePalette.hover,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14,
                  8,
                  compact ? 6 : 10,
                  8,
                ),
                child: Row(
                  children: [
                    SizedBox(width: 26, child: _buildLeading()),
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
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
                            style: OnlineText.title.copyWith(
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w500,
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
                            style: OnlineText.caption.copyWith(
                              color: OnlinePalette.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      OnlineTag(
                        text: qualityLabel,
                        color: OnlinePalette.textFaint,
                      ),
                      if (roomy) ...[
                        const SizedBox(width: 6),
                        OnlineTag(
                          text:
                              onlineSearchers[track.source]?.label ??
                              track.source,
                          color: OnlinePalette.primaryLight,
                        ),
                      ],
                    ],
                    const SizedBox(width: 10),
                    // 固定宽度 + 等宽数字：行与行的时长竖着对齐。
                    SizedBox(
                      width: 40,
                      child: Text(
                        track.interval,
                        textAlign: TextAlign.right,
                        style: OnlineText.numeric.copyWith(
                          color: OnlinePalette.textFaint,
                        ),
                      ),
                    ),
                    DownloadButton(track: track, onDownload: onDownload),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 行首：解析中转圈，当前播放显示音律图标，其余显示序号。
  Widget _buildLeading() {
    if (isResolving) {
      // Center 给宽松约束：否则外层 SizedBox 的紧宽度会把转圈压成扁圆。
      return Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: OnlinePalette.primaryLight,
          ),
        ),
      );
    }
    if (isCurrent) {
      return Icon(
        Icons.equalizer_rounded,
        size: 18,
        color: OnlinePalette.primaryLight,
      );
    }
    return Text(
      '$index',
      style: OnlineText.caption.copyWith(color: OnlinePalette.textFaint),
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
          padding: const EdgeInsets.all(8),
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

/// 播放顺序按钮：点开后用 [MenuAnchor] 在图标右上角弹一个小菜单。
///
/// 和本地音乐的 `playModeButton` 不同，这里只改 [playModeNotifier]，
/// 由页面决定要不要动全局队列（在线队列里只有当前一首）。
class PlayOrderButton extends StatelessWidget {
  const PlayOrderButton({
    super.key,
    required this.iconSize,
    required this.onModeChange,
  });

  final double iconSize;
  final void Function(int) onModeChange;

  static const _labels = ['列表循环', '随机播放', '单曲循环'];
  static const _icons = [
    Icons.repeat_rounded,
    Icons.shuffle_rounded,
    Icons.repeat_one_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: playModeNotifier,
      builder: (context, mode, _) {
        // 0/1/2 之外的脏值当列表循环处理，别让取图标时越界。
        final index = mode == 1 ? 1 : (mode == 2 ? 2 : 0);
        late MenuController menuController;
        return MenuAnchor(
          style: MenuStyle(
            // 贴图标右上角弹；底栏放不下时 MenuAnchor 自己翻到上方。
            alignment: Alignment.topRight,
            backgroundColor: WidgetStatePropertyAll(OnlinePalette.surfaceAlt),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 6),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            elevation: const WidgetStatePropertyAll(6),
          ),
          builder: (context, controller, child) {
            menuController = controller;
            return IconButton(
              tooltip: '播放顺序',
              color: OnlinePalette.textDim,
              iconSize: iconSize,
              onPressed: () {
                if (playQueue.isEmpty) return;
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: Icon(_icons[index]),
            );
          },
          menuChildren: [
            for (var i = 0; i < 3; i++)
              SizedBox(
                width: 160,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(_icons[i], color: OnlinePalette.textDim),
                  title: Text(
                    _labels[i],
                    style: TextStyle(color: OnlinePalette.text),
                  ),
                  trailing: index == i
                      ? Icon(Icons.check_rounded, color: OnlinePalette.primary)
                      : null,
                  onTap: () {
                    menuController.close();
                    onModeChange(i);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

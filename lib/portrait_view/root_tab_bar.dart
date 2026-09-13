import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';

// the root tabs (and their order) the app ships with; users can reorder them
// by dragging a tab around
const List<String> rootLayerLabels = <String>[
  'ranking',
  'recently',
  'songs',
  'playlists',
  'artists',
  'albums',
  'folders',
];

// current order of the root tabs, restored from setting.json
final rootTabOrderNotifier = ValueNotifier<List<String>>(
  List<String>.of(rootLayerLabels),
);

int rootTabIndexOf(String label) => rootTabOrderNotifier.value.indexOf(label);

String rootTabText(AppLocalizations l10n, String label) {
  switch (label) {
    case 'artists':
      return l10n.artists;
    case 'albums':
      return l10n.albums;
    case 'folders':
      return l10n.folders;
    case 'songs':
      return l10n.songs;
    case 'ranking':
      return l10n.ranking;
    case 'recently':
      return l10n.recently;
    case 'playlists':
      return l10n.playlists;
    default:
      return label;
  }
}

/// Called by [Setting.load] with whatever was stored in setting.json. Unknown
/// labels are dropped and missing ones are appended, so a version that adds or
/// removes a root tab can never end up with a broken tab bar.
void loadRootTabOrder(Object? saved) {
  final order = <String>[];

  if (saved is List) {
    for (final label in saved.whereType<String>()) {
      if (rootLayerLabels.contains(label) && !order.contains(label)) {
        order.add(label);
      }
    }
  }

  for (final label in rootLayerLabels) {
    if (!order.contains(label)) {
      order.add(label);
    }
  }

  rootTabOrderNotifier.value = order;
}

/// Moves the tab at [fromIndex] into the slot currently held by [toIndex].
/// The selected layer does not change, [PortraitView] keeps the highlight on
/// it through [rootTabOrderNotifier].
void moveRootTab(int fromIndex, int toIndex) {
  final order = List<String>.of(rootTabOrderNotifier.value);
  if (fromIndex < 0 || fromIndex >= order.length) {
    return;
  }
  if (toIndex < 0 || toIndex >= order.length || toIndex == fromIndex) {
    return;
  }

  order.insert(toIndex, order.removeAt(fromIndex));
  rootTabOrderNotifier.value = order;

  setting.save();
}

// shared by every root page so all tab bars stay in sync; created by PortraitView
late TabController rootTabController;

class RootTabBar extends StatelessWidget {
  const RootTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        sidebarColor.valueNotifier,
        highlightTextColor.valueNotifier,
        textColor.valueNotifier,
        rootTabOrderNotifier,
      ]),
      builder: (context, child) {
        final order = rootTabOrderNotifier.value;

        return Material(
          color: sidebarColor.value,
          child: TabBar(
            controller: rootTabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            dividerColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            labelColor: highlightTextColor.value,
            unselectedLabelColor: textColor.value,
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            onTap: (index) {
              layersManager.switchRootLayer(order[index]);
            },
            tabs: [
              for (int i = 0; i < order.length; i++)
                _RootTab(
                  key: ValueKey(order[i]),
                  index: i,
                  label: order[i],
                  text: rootTabText(l10n, order[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RootTab extends StatelessWidget {
  const _RootTab({
    super.key,
    required this.index,
    required this.label,
    required this.text,
  });

  final int index;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != label,
      onAcceptWithDetails: (details) {
        moveRootTab(rootTabIndexOf(details.data), index);
      },
      builder: (context, candidateData, rejectedData) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: candidateData.isEmpty
                ? Colors.transparent
                : selectedItemColor.value,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _dragSource(),
        );
      },
    );
  }

  Widget _dragSource() {
    final tab = Tab(text: text);
    final childWhenDragging = Opacity(opacity: 0.3, child: tab);

    final feedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sidebarColor.value,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: highlightTextColor.value,
          ),
        ),
      ),
    );

    // touch screens need a long press, otherwise dragging would fight with
    // scrolling the tab bar sideways; a mouse has no such conflict
    if (isMobile) {
      return LongPressDraggable<String>(
        data: label,
        axis: Axis.horizontal,
        delay: const Duration(milliseconds: 300),
        hapticFeedbackOnStart: true,
        dragAnchorStrategy: childDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: tab,
      );
    }

    return Draggable<String>(
      data: label,
      axis: Axis.horizontal,
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: tab,
    );
  }
}

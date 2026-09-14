import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/data/setting.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
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

// setting.save() writes setting.json synchronously, so it must not run inside
// the callback that ends a drag - keep it out of that frame
Timer? _saveOrderTimer;

void _scheduleSaveOrder() {
  _saveOrderTimer?.cancel();
  _saveOrderTimer = Timer(const Duration(milliseconds: 400), setting.save);
}

/// Moves the tab at [fromIndex] into the slot currently held by [toIndex].
/// The selected layer does not change, the highlight follows
/// [sidebarHighlighLabel] through [rootTabOrderNotifier].
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

  _scheduleSaveOrder();
}

/// A horizontal [ReorderableListView] instead of a [TabBar]: a [TabBar] needs
/// its [TabController] to keep pointing at the same children, which reordering
/// breaks, and a [Draggable] on top of it fights the tab bar's own sideways
/// scrolling. The list brings the drop animation, the edge auto scroll and the
/// drag proxy the hand written version was missing.
///
/// The highlight comes from [sidebarHighlighLabel], the same source the wide
/// layout sidebar uses, so there is no controller left to fall out of sync.
class RootTabBar extends StatelessWidget {
  const RootTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        rootTabOrderNotifier,
        sidebarHighlighLabel,
        sidebarColor.valueNotifier,
        highlightTextColor.valueNotifier,
        textColor.valueNotifier,
        selectedItemColor.valueNotifier,
      ]),
      builder: (context, child) {
        final order = rootTabOrderNotifier.value;
        final highlightLabel = sidebarHighlighLabel.value;

        // the tab bar sits directly on the layer's own background (vivid /
        // light / dark all come from here), so it must not paint a color of
        // its own - otherwise it shows up as a slightly different band
        return Material(
          color: Colors.transparent,
          child: SizedBox(
            height: 46,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: order.length,
              onReorderStart: (index) => tryVibrate(),
              onReorderItem: moveRootTab,
              proxyDecorator: _proxyDecorator,
              itemBuilder: (context, index) {
                final label = order[index];
                final key = ValueKey(label);

                final tab = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _RootTab(
                    text: rootTabText(l10n, label),
                    selected: label == highlightLabel,
                    onTap: () => layersManager.switchRootLayer(label),
                  ),
                );

                // touch screens need a long press, otherwise dragging a tab
                // would fight with scrolling the tab bar sideways; a mouse has
                // no such conflict and can start dragging right away
                if (isMobile) {
                  return ReorderableDelayedDragStartListener(
                    key: key,
                    index: index,
                    child: tab,
                  );
                }

                return ReorderableDragStartListener(
                  key: key,
                  index: index,
                  child: tab,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// a tab is transparent while it is not selected, so the proxy has to bring its
// own chip background - otherwise the dragged label floats over the page
Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      return Material(
        color: Colors.transparent,
        child: DecoratedBox(
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
          child: child,
        ),
      );
    },
  );
}

class _RootTab extends StatelessWidget {
  const _RootTab({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? selectedItemColor.value : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? highlightTextColor.value : textColor.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

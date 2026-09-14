import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
import 'package:sylvakru/layer/layers_manager.dart';

// the root tabs, in the order the app shows them
const List<String> rootLayerLabels = <String>[
  'ranking',
  'recently',
  'songs',
  'playlists',
  'artists',
  'albums',
  'folders',
];

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

/// A horizontal [ListView] instead of a [TabBar]: a [TabBar] needs its
/// [TabController] to keep pointing at the same children, while the highlight
/// here is read straight from [sidebarHighlighLabel], the same source the wide
/// layout sidebar uses, so there is no controller to fall out of sync.
///
/// The tab bar sits directly on the layer's own background (vivid / light /
/// dark all come from here), so it must not paint a color of its own -
/// otherwise it shows up as a slightly different band.
class RootTabBar extends StatelessWidget {
  const RootTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        sidebarHighlighLabel,
        highlightTextColor.valueNotifier,
        textColor.valueNotifier,
        selectedItemColor.valueNotifier,
      ]),
      builder: (context, child) {
        final highlightLabel = sidebarHighlighLabel.value;

        return Material(
          color: Colors.transparent,
          child: SizedBox(
            height: 46,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: rootLayerLabels.length,
              itemBuilder: (context, index) {
                final label = rootLayerLabels[index];

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _RootTab(
                    text: rootTabText(l10n, label),
                    selected: label == highlightLabel,
                    onTap: () => layersManager.switchRootLayer(label),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
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

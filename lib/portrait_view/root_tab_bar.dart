import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';

const List<String> rootLayerLabels = <String>[
  'artists',
  'albums',
  'folders',
  'songs',
  'ranking',
  'recently',
  'playlists',
  'settings',
];

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
      ]),
      builder: (context, child) {
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
              layersManager.switchRootLayer(rootLayerLabels[index]);
            },
            tabs: [
              Tab(text: l10n.artists),
              Tab(text: l10n.albums),
              Tab(text: l10n.folders),
              Tab(text: l10n.songs),
              Tab(text: l10n.ranking),
              Tab(text: l10n.recently),
              Tab(text: l10n.playlists),
              Tab(text: l10n.settings),
            ],
          ),
        );
      },
    );
  }
}

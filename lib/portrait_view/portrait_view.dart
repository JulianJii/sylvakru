import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/portrait_view/play_bar.dart';
import 'package:sylvakru/portrait_view/root_tab_bar.dart';

class PortraitView extends StatefulWidget {
  const PortraitView({super.key});

  @override
  State<StatefulWidget> createState() => _PortraitViewState();
}

class _PortraitViewState extends State<PortraitView>
    with SingleTickerProviderStateMixin {
  // keep tab highlight in sync with switches triggered elsewhere,
  // e.g. removing the current playlist falls back to songs,
  // and with the selected tab being dragged to another position
  void syncTabFromManager() {
    final index = rootTabIndexOf(sidebarHighlighLabel.value);
    if (index < 0 || rootTabController.index == index) {
      return;
    }
    rootTabController.animateTo(index);
  }

  @override
  void initState() {
    super.initState();

    final index = rootTabIndexOf(sidebarHighlighLabel.value);
    rootTabController = TabController(
      length: rootLayerLabels.length,
      vsync: this,
      initialIndex: index < 0 ? 0 : index,
    );
    layersManager.switchNotifier.addListener(syncTabFromManager);
    rootTabOrderNotifier.addListener(syncTabFromManager);

    if (index < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        layersManager.switchRootLayer('songs');
      });
    }
  }

  @override
  void dispose() {
    layersManager.switchNotifier.removeListener(syncTabFromManager);
    rootTabOrderNotifier.removeListener(syncTabFromManager);
    rootTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // fills the status bar area with the same color as the tab bar,
    // like the sidebar does in landscape
    return ValueListenableBuilder(
      valueListenable: sidebarColor.valueNotifier,
      builder: (context, sidebarBg, child) {
        return Scaffold(
          backgroundColor: sidebarBg,
          resizeToAvoidBottomInset: false,
          body: child,
        );
      },
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: layersManager.switchNotifier,
                    builder: (context, _, _) {
                      return Stack(
                        children: layersManager.rootPageMap.values.map((
                          page,
                        ) {
                          return Visibility(
                            visible: page == layersManager.topRootPage,
                            maintainState: true,
                            child: page,
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          Positioned(left: 20, right: 20, bottom: 40, child: PlayBar()),
        ],
      ),
    );
  }
}

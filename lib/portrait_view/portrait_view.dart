import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/portrait_view/play_bar.dart';
import 'package:sylvakru/portrait_view/root_tab_bar.dart';

class PortraitView extends StatefulWidget {
  const PortraitView({super.key});

  @override
  State<StatefulWidget> createState() => _PortraitViewState();
}

class _PortraitViewState extends State<PortraitView> {
  @override
  void initState() {
    super.initState();

    // the highlight is read straight from sidebarHighlighLabel by RootTabBar,
    // so there is no tab controller to keep in sync here anymore. The stored
    // order can still hold a layer that is not a root tab at all (settings, a
    // playlist), in which case fall back to songs.
    if (rootTabIndexOf(sidebarHighlighLabel.value) < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        layersManager.switchRootLayer('songs');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          ValueListenableBuilder(
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

          Positioned(left: 20, right: 20, bottom: 40, child: PlayBar()),
        ],
      ),
    );
  }
}

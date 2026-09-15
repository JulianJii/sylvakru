import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/landscape_view/sidebar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/portrait_view/my_app_bar.dart';
import 'package:sylvakru/portrait_view/play_bar.dart';
import 'package:sylvakru/portrait_view/root_tab_bar.dart';

/// The narrow home: one top bar and one tab bar on top, the tab pages loaded in
/// below as the content, so the tab bar lives here instead of being repeated by
/// every page.
class PortraitView extends StatefulWidget {
  const PortraitView({super.key});

  @override
  State<StatefulWidget> createState() => _PortraitViewState();
}

class _PortraitViewState extends State<PortraitView>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  // one per root tab, filled by the pages themselves (see [RootTabSlot])
  final List<RootTabSlot> _slots = List.generate(
    rootLayerLabels.length,
    (_) => RootTabSlot(),
  );

  int _shownIndex = 0;

  @override
  void initState() {
    super.initState();

    // the stored layer can be one that is not a root tab at all (settings, a
    // playlist), in which case fall back to songs.
    var label = sidebarHighlighLabel.value;
    if (!rootLayerLabels.contains(label)) {
      label = 'songs';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        layersManager.switchRootLayer(label);
      });
    }
    _shownIndex = rootLayerLabels.indexOf(label);

    for (final slot in _slots) {
      slot.onFirstFill = _refresh;
    }

    _controller = TabController(
      length: rootLayerLabels.length,
      initialIndex: _shownIndex,
      vsync: this,
    )..addListener(_onTabChanged);

    sidebarHighlighLabel.addListener(_onLabelChanged);
    // a pushed / popped detail page changes whether the bars are shown
    layersManager.detailChangeNotifier.addListener(_refresh);
    // dropped layers (another music source, cleared data) have to be rebuilt
    layersManager.switchNotifier.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabChanged);
    _controller.dispose();
    sidebarHighlighLabel.removeListener(_onLabelChanged);
    layersManager.detailChangeNotifier.removeListener(_refresh);
    layersManager.switchNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Tapping a tab and swiping the pages both land here, the same tray the wide
  /// layout switches through, so background, highlight and details follow.
  void _onTabChanged() {
    if (_controller.index != _shownIndex) {
      setState(() => _shownIndex = _controller.index);
    }

    // an animateTo of our own is still running, the label is already right
    if (_controller.indexIsChanging) {
      return;
    }

    final label = rootLayerLabels[_controller.index];
    if (sidebarHighlighLabel.value != label) {
      layersManager.switchRootLayer(label);
    }
  }

  void _onLabelChanged() {
    final index = rootLayerLabels.indexOf(sidebarHighlighLabel.value);
    if (index >= 0 && index != _controller.index) {
      _controller.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    // a detail page is pushed inside the layers own navigators, which sit below
    // everything here, so the top bar and tab bar step aside for it
    final showBars =
        layersManager.detailWidgetMap[layersManager.topRootLayer] == null;

    // the app bar is the status bar plus the toolbar and the tab bar, and this
    // context is still outside the Scaffold, so its top padding is the status
    // bar part - below, in the body, it is gone
    final topInset = MediaQuery.paddingOf(context).top + rootTabBarInset;

    final pageArea = Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: TabBarView(
        controller: _controller,
        children: [
          for (var i = 0; i < rootLayerLabels.length; i++)
            RootTabScope(
              slot: _slots[i],
              topInset: topInset,
              child: _KeepAlive(child: _RootTabPage(rootLayerLabels[i])),
            ),
        ],
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      appBar: showBars
          ? MyAppBar(
              actions: _slots[_shownIndex].actions,
              bottom: RootTabBar(controller: _controller),
            )
          : null,
      body: Stack(
        children: [
          // behind the bars the body keeps the height of the app bar as its
          // top padding, which the pages below would then pad again - they only
          // leave [rootTabBarInset] for the bars of the home, like they did for
          // their own top bar before. With a detail page open the padding is
          // left alone, that page brings its own top bar.
          showBars
              ? MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: pageArea,
                )
              : pageArea,

          Positioned(left: 20, right: 20, bottom: 40, child: PlayBar()),
        ],
      ),
    );
  }
}

/// A tab page, only handed to its layer when this tab is actually built - the
/// pages are as expensive as they look and a tab nobody opened should not be
/// built.
class _RootTabPage extends StatelessWidget {
  const _RootTabPage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return layersManager.rootPageFor(label);
  }
}

/// The old layout kept every root page alive through `maintainState: true`, and
/// a tab that forgets its search / scroll position is what that avoided.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

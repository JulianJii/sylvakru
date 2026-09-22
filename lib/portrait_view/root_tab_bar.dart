import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/services/interaction.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/online_music/online_music_page.dart';

// the root tabs, in the order the app shows them
const List<String> rootLayerLabels = <String>[
  'frequently',
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
    case 'frequently':
      return l10n.frequently;
    case 'recently':
      return l10n.recently;
    case 'playlists':
      return l10n.playlists;
    default:
      return label;
  }
}

/// What the shell's top bar (toolbar) and the tab bar take up at the top of the
/// screen: the toolbar plus the text [TabBar] below it.
const double rootTabBarInset = kToolbarHeight + rootTabBarHeight;

/// A text [TabBar]: its tabs are 46 tall and the underline under them is 2.
const double rootTabBarHeight = 48;

/// One per root tab, held by the shell. A tab page writes its own toolbar
/// actions in here while it builds, so a single top bar can show the actions of
/// whichever tab is on screen instead of every page carrying a top bar.
class RootTabSlot {
  List<Widget>? actions;

  /// Set by the shell. The shell builds its top bar before the page of a tab
  /// builds, so the first time a page publishes its actions one more frame is
  /// asked for.
  VoidCallback? onFirstFill;

  void set(List<Widget> value) {
    final fill = onFirstFill;
    if (actions == null && fill != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fill());
    }
    actions = value;
  }
}

/// Hands a tab page the [RootTabSlot] of the tab it is rendered as, and how
/// much room the bars of the home take above it.
///
/// The height has to come from the shell: the body below the bars no longer
/// knows the status bar, removing the top padding takes it out of `viewPadding`
/// as well, and a page that guesses [rootTabBarInset] alone then hides its first
/// row behind the tab bar.
class RootTabScope extends InheritedWidget {
  const RootTabScope({
    super.key,
    required this.slot,
    required this.topInset,
    required super.child,
  });

  final RootTabSlot slot;

  /// Top bar + tab bar + status bar, as measured where the shell still sees it.
  final double topInset;

  static RootTabScope? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<RootTabScope>();
  }

  @override
  bool updateShouldNotify(RootTabScope oldWidget) => slot != oldWidget.slot;
}

/// What a root tab page puts on screen: the home already draws the one top bar
/// and the tab bar above it, so the page only publishes the actions that go
/// before the settings button [rootTabMoreButton] every tab ends its row with,
/// and leaves [RootTabScope.topInset] free for them.
Widget rootTabContent(
  BuildContext context,
  List<Widget> actions,
  Widget content,
) {
  final scope = RootTabScope.maybeOf(context);
  scope?.slot.set([
    ...actions,
    rootTabOnlineMusicButton(context),
    rootTabMoreButton(context),
  ]);

  return Padding(
    padding: EdgeInsets.only(top: scope?.topInset ?? rootTabBarInset),
    child: content,
  );
}

/// The online music entry, right before the settings button every root tab
/// ends its row with.
Widget rootTabOnlineMusicButton(BuildContext context) {
  return IconButton(
    tooltip: "网络音乐",
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    icon: Icon(Icons.cloud_outlined),
    onPressed: () {
      tryVibrate();
      openOnlineMusicPage(context);
    },
  );
}

/// The settings entry every root tab ends its action row with. It is the same
/// button on all of them, so the home draws it itself instead of every page
/// passing one in.
Widget rootTabMoreButton(BuildContext context) {
  final l10n = AppLocalizations.of(context);

  return Builder(
    builder: (buttonContext) {
      return IconButton(
        tooltip: l10n.more,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.more_vert),
        onPressed: () {
          tryVibrate();

          showContextMenu(context, [
            MenuItem(
              iconData: Icons.settings_outlined,
              text: l10n.settings,
              callback: () => layersManager.openSettings(),
            ),
          ], menuAnchor(buttonContext));
        },
      );
    },
  );
}

/// The one tab bar of the portrait home, the official one driven by the shell's
/// [TabController] - so tapping a tab, swiping the pages and the underline all
/// stay in sync through the framework instead of a hand rolled list.
///
/// It sits directly on the layer's own background (vivid / light / dark all come
/// from there), so it must not paint a color of its own.
class RootTabBar extends StatelessWidget implements PreferredSizeWidget {
  const RootTabBar({super.key, required this.controller});

  final TabController controller;

  @override
  Size get preferredSize => const Size.fromHeight(rootTabBarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        highlightTextColor.valueNotifier,
        textColor.valueNotifier,
      ]),
      builder: (context, child) {
        final labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
        final unselectedStyle = TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
        );

        return TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          indicatorSize: TabBarIndicatorSize.label,
          indicatorAnimation: TabIndicatorAnimation.linear,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: highlightTextColor.value, width: 2),
          ),
          // the bar is a part of the layer's own background, a divider would
          // show up as a band of its own
          dividerColor: Colors.transparent,
          labelColor: highlightTextColor.value,
          unselectedLabelColor: textColor.value,
          labelStyle: labelStyle,
          unselectedLabelStyle: unselectedStyle,
          tabs: [
            for (final label in rootLayerLabels)
              Tab(text: rootTabText(l10n, label)),
          ],
        );
      },
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/portrait_view/my_app_bar.dart';
import 'package:sylvakru/portrait_view/root_tab_bar.dart';

/// The plain look of the portrait home: one top bar with the tab bar under it,
/// the tab pages below. What the bars take has to match what the pages leave
/// free, status bar included - off by the status bar is the first row of every
/// tab hidden behind the tab bar, and the pages cannot measure the status bar
/// themselves (the shell has already removed the top padding of the body).
void main() {
  testWidgets('the tab content starts below the bars, status bar included', (
    tester,
  ) async {
    await tester.pumpWidget(_host(statusBar: 24));

    final barsHeight = tester.getSize(find.byType(AppBar)).height;
    expect(barsHeight, 24 + rootTabBarInset);
    expect(
      tester.getTopLeft(find.text('page-${rootLayerLabels.first}')).dy,
      barsHeight,
    );

    // one tab per root layer, labelled in the current language
    final l10n = AppLocalizations.of(tester.element(find.byType(RootTabBar)));
    for (final label in rootLayerLabels) {
      expect(find.text(rootTabText(l10n, label)), findsOneWidget);
    }
  });

  testWidgets('a tab page publishes its actions and uses the inset it gets', (
    tester,
  ) async {
    final slot = RootTabSlot();
    var filled = 0;
    slot.onFirstFill = () => filled++;

    await tester.pumpWidget(
      _host(statusBar: 24, slot: slot, page: const _Page('test')),
    );
    await tester.pump();

    expect(slot.actions, isNotNull);
    // the actions of the page plus the online music and settings buttons
    expect(slot.actions!.length, 3);
    expect(filled, 1, reason: 'the shell gets one frame to pick them up');
    expect(
      tester.getTopLeft(find.text('page-test')).dy,
      24 + rootTabBarInset,
      reason: 'the page keeps clear of the bars of the home',
    );
  });
}

Widget _host({required double statusBar, RootTabSlot? slot, Widget? page}) {
  final insets = EdgeInsets.only(top: statusBar);
  return MediaQuery(
    data: MediaQueryData(padding: insets, viewPadding: insets),
    child: Localizations(
      locale: const Locale('en'),
      delegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      child: _Shell(slot: slot, page: page),
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({this.slot, this.page});

  final RootTabSlot? slot;
  final Widget? page;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: rootLayerLabels.length,
    vsync: this,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // what the shell does: it still sees the status bar here, and below the
    // bars the body has lost it
    final topInset = MediaQuery.paddingOf(context).top + rootTabBarInset;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: MyAppBar(bottom: RootTabBar(controller: _controller)),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: TabBarView(
          controller: _controller,
          children: [
            for (var i = 0; i < rootLayerLabels.length; i++)
              RootTabScope(
                slot: widget.slot ?? RootTabSlot(),
                topInset: topInset,
                child: widget.page ?? _Page(rootLayerLabels[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return rootTabContent(context, const [
      Text('actions'),
    ], Align(alignment: Alignment.topLeft, child: Text('page-$label')));
  }
}

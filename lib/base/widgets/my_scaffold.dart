import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/portrait_view/my_app_bar.dart';

/// The shared portrait page scaffold of upstream.
///
/// This fork dropped `custom_appbar_leading.dart` together with the drawer
/// navigation, so the top bar comes from the local [MyAppBar]: a page without a
/// [label] is a root page and gets the root top bar, a page with one is stacked
/// on top of that layer and gets the back arrow.
Widget myScaffold({
  required BuildContext context,
  required Widget body,
  String label = '',
  String? title,
  List<Widget>? actions,
}) {
  return Scaffold(
    backgroundColor: Colors.transparent,
    resizeToAvoidBottomInset: false,
    appBar: label.isEmpty
        ? MyAppBar(actions: actions)
        : MyAppBar.detail(
            title: title,
            backLabel: label,
            actions: actions,
          ),
    body: body,
  );
}

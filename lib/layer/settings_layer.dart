import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/widgets/my_navigator.dart';
import 'package:sylvakru/base/widgets/settings_list.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/landscape_view/title_bar.dart';
import 'package:sylvakru/layer/layers_manager.dart';
import 'package:sylvakru/portrait_view/my_app_bar.dart';

part '../portrait_view/pages/settings_page.dart';

final GlobalKey<NavigatorState> settingsKey = GlobalKey();
final settingsVisibleNotifier = ValueNotifier(true);

class SettingsLayer extends StatelessWidget {
  const SettingsLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return myNavigator(
      key: settingsKey,
      visibleNotifier: settingsVisibleNotifier,
      // in portrait settings is pushed as its own route (see
      // LayersManager.openSettings); this view is only reached when the layer
      // is switched in instead, so it keeps the back arrow as well
      pageViewBuilder: () => SettingsPage(),
      panelViewBuilder: () => Column(
        children: [
          TitleBar(),
          Expanded(child: SettingsList()),
        ],
      ),
    );
  }
}

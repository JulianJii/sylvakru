import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/l10n/generated/app_localizations.dart';
import 'package:sylvakru/layer/layers_manager.dart';

/// The one top bar the portrait pages share.
///
/// It has exactly two shapes and the constructor you pick says which one you
/// get, so a root tab page can no longer grow a back arrow the way the songs /
/// ranking / recently tabs used to:
///
/// * `MyAppBar()` - a root tab page. Shows the localized app name and **never** a
///   leading widget, because a tab is not somewhere you go back from.
/// * `MyAppBar.detail()` - a page stacked on top of a root layer. Shows a back
///   arrow instead of the title.
class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Top bar of a root tab page (songs / ranking / recently / folders /
  /// artists / albums / playlists).
  const MyAppBar({super.key, this.actions})
    : title = null,
      backLabel = null,
      onBack = null,
      centerTitle = false;

  /// Top bar of a page stacked on top of a root layer. The back arrow returns
  /// to [backLabel] through the layer manager, or runs [onBack] when the page
  /// needs its own way out.
  const MyAppBar.detail({
    super.key,
    this.title,
    this.backLabel,
    this.onBack,
    this.actions,
    this.centerTitle = true,
  }) : assert(
         backLabel != null || onBack != null,
         'a detail top bar needs a backLabel or an onBack',
       );

  /// Root pages default it to the localized app name; a detail page can name itself
  /// or show no title at all (the artist / album / folder / playlist detail
  /// pages draw their own large header in the body).
  final String? title;

  /// Root layer the back arrow pops back to.
  final String? backLabel;

  /// Overrides what the back arrow does. Used by the settings page, which is
  /// left either by popping its route or by switching back to a root layer.
  final VoidCallback? onBack;

  final List<Widget>? actions;

  final bool centerTitle;

  bool get _isDetail => backLabel != null || onBack != null;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    // listened to here instead of by each page, so a const top bar still
    // follows a theme switch
    return ValueListenableBuilder(
      valueListenable: mainPageThemeNotifier,
      builder: (context, theme, child) {
        // a root tab bar shows the localized app name; a detail page names
        // itself (or shows nothing)
        final titleText = _isDetail ? title : AppLocalizations.of(context).sylvakru;
        return AppBar(
          automaticallyImplyLeading: false,
          leading: _isDetail
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: onBack ?? () => layersManager.popDetail(backLabel!),
                )
              : null,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: theme == .dark ? .light : .dark,
          centerTitle: centerTitle,
          title: titleText == null
              ? null
              : Text(
                  titleText,
                  style: _isDetail
                      ? null
                      : const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                ),
          actions: actions,
        );
      },
    );
  }
}

part of '../../layer/folders_layer.dart';

extension FoldersPage on FoldersLayer {
  Widget pageView(BuildContext context) {
    // the portrait home draws the one top bar and the tab bar, so this page
    // only publishes the action it puts in that top bar
    return rootTabContent(
      context,
      [moreButton(context)],
      ListView.builder(
        itemCount: library.folderList.length,
        itemBuilder: (_, index) {
          final folder = library.folderList[index];
          return ListTile(
            leading: ValueListenableBuilder(
              valueListenable: folder.changeNotifier,
              builder: (context, value, child) {
                final coverSong = getFirstSong(folder.songList);
                return ListenableBuilder(
                  listenable: Listenable.merge([coverSong?.updateNotifier]),
                  builder: (_, _) {
                    return Hero(
                      tag: (coverSong?.picture.id ?? '') + folder.id,
                      transitionOnUserGestures: true,
                      child: CoverArtWidget(
                        size: 50,
                        borderRadius: 5,
                        picture: coverSong?.picture,
                      ),
                    );
                  },
                );
              },
            ),
            // only the folder itself, not the whole path it was added with
            title: Text(p.basename(folder.id)),
            onTap: () {
              layersManager.pushDetail('folders', folder);
            },
          );
        },
      ),
    );
  }

  /// The one action this tab has: the settings entry every other root tab
  /// offers at the end of its action row. Searching / sorting a folder list is
  /// not something a user does, so there is no search field or sort button next
  /// to it.
  Widget moreButton(BuildContext context) {
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

  // anchor point for popup menus opened from toolbar icon buttons
  Offset menuAnchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return Offset.zero;
    }
    return box.localToGlobal(box.size.bottomRight(Offset.zero));
  }
}

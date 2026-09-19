part of '../../layer/folders_layer.dart';

extension FoldersPage on FoldersLayer {
  Widget pageView(BuildContext context) {
    // the portrait home draws the one top bar and the tab bar, so this page
    // only publishes what goes in that top bar - here nothing, the settings
    // button at the end of the row comes from the home itself
    return rootTabContent(
      context,
      const [],
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

}

part of '../../base/widgets/song_list.dart';

extension _SongListPage on _SongListState {
  Widget pageView(BuildContext context) {
    final actions = topBarActions(context);

    // a root tab (songs / ranking / recently) is rendered into the portrait
    // home, which owns the one top bar and the tab bar - this page only says
    // what goes in the top bar, the home adds the settings button itself. A page
    // stacked on top of a root layer keeps its own top bar with the back arrow.
    if (widget.isRoot && playlist == null) {
      return rootTabContent(context, actions, contentWithStack());
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          topBar(context, [...actions, moreButton(context)]),
          Expanded(child: contentWithStack()),
        ],
      ),
    );
  }

  Widget topBar(BuildContext context, List<Widget> actions) {
    return widget.isRoot
        ? MyAppBar(actions: actions)
        : MyAppBar.detail(backLabel: rootLabel, actions: actions);
  }

  List<Widget> topBarActions(BuildContext context) {
    final actions = <Widget>[
      ValueListenableBuilder(
        valueListenable: currentSongListNotifier,
        builder: (context, value, child) {
          return MySearchField(
            key: ValueKey(getFirstSong(songList)),
            hintText: AppLocalizations.of(context).searchSongs,
            textController: textController,
            useCurrentSong: false,
          );
        },
      ),
      selectButton(context),
      if (!isFrequently && !isRecently) sortButton(context),
      if (playlist != null && playlist!.isNotFavorite) deleteButton(context),
    ];

    return actions;
  }

  Widget selectButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IconButton(
      tooltip: l10n.select,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: ImageIcon(selectImage),
      onPressed: () {
        tryVibrate();

        for (var e in isSelectedNotifierMap.values) {
          e.value = false;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ValueListenableBuilder(
              valueListenable: currentSongListNotifier,
              builder: (context, currentSongList, child) {
                return SelectableSongListPage(
                  songList: currentSongList,
                  playlist: playlist,
                  folder: folder,
                  isFrequently: isFrequently,
                  isRecently: isRecently,
                  isLibrary: isLibrary,
                  reorderable: reorderable,
                  isSelectedNotifierMap: isSelectedNotifierMap,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget deleteButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IconButton(
      tooltip: l10n.delete,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: ImageIcon(deleteImage),
      onPressed: () async {
        tryVibrate();

        if (await showConfirmDialog(context, l10n.delete)) {
          layersManager.removeLayerIfNeed(playlist!);
          playlistManager.deletePlaylist(playlist!);
        }
      },
    );
  }

  Widget sortButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Builder(
      builder: (buttonContext) {
        return IconButton(
          tooltip: l10n.sortSongs,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: ImageIcon(sequenceImage),
          onPressed: () {
            tryVibrate();

            List<String> orderText = [
              l10n.defaultText,
              l10n.titleAscending,
              l10n.titleDescending,
              l10n.artistAscending,
              l10n.artistDescending,
              l10n.albumAscending,
              l10n.albumDescending,
              l10n.durationAscending,
              l10n.durationDescending,
            ];
            if (isLibrary && (isNotStreamSource) || folder != null) {
              orderText.add(l10n.modifiedTimeAscending);
              orderText.add(l10n.modifiedTimedescending);
              orderText.add(l10n.randomizeTemp);
              orderText.add(l10n.randomizePermanent);
            }

            final items = <MenuItem>[];
            for (int i = 0; i < orderText.length; i++) {
              items.add(
                MenuItem(
                  iconData: sortTypeNotifier.value == i ? Icons.check : null,
                  text: orderText[i],
                  callback: () async {
                    if (i == 12) {
                      if (!await showConfirmDialog(
                        context,
                        l10n.cannotBeUndone,
                      )) {
                        return;
                      }
                      sortTypeNotifier.value = 0;
                      if (isLibrary) {
                        library.shuffle();
                      } else {
                        folder!.shuffle();
                      }
                    } else {
                      if (i == 11 && sortTypeNotifier.value == 11) {
                        updateSongList();
                      }
                      sortTypeNotifier.value = i;
                    }
                  },
                ),
              );
            }

            showContextMenu(context, items, menuAnchor(buttonContext));
          },
        );
      },
    );
  }

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

  Widget contentWithStack() {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              listIsScrollingNotifier.value = true;
              if (timer != null) {
                timer!.cancel();
                timer = null;
              }
            } else {
              if (listIsScrollingNotifier.value) {
                timer ??= Timer(const Duration(milliseconds: 3000), () {
                  listIsScrollingNotifier.value = false;
                  timer = null;
                });
              }
            }
            return false;
          },
          child: pageContent(),
        ),
        Positioned(
          right: 30,
          bottom: 180,
          child: ValueListenableBuilder(
            valueListenable: listIsScrollingNotifier,
            builder: (context, value, child) {
              if (!value) {
                return SizedBox.shrink();
              }
              return IconButton(
                onPressed: () {
                  scrollController.animateTo(
                    0,
                    duration: Duration(milliseconds: 250),
                    curve: Curves.linear,
                  );
                },
                icon: ImageIcon(topArrowImage),
              );
            },
          ),
        ),

        Positioned(
          right: 30,
          bottom: 120,
          child: MyLocation(
            scrollController: scrollController,
            listIsScrollingNotifier: listIsScrollingNotifier,
            currentSongListNotifier: currentSongListNotifier,
            offset: 300 - MediaQuery.heightOf(context) / 2,
          ),
        ),
      ],
    );
  }

  Widget pageHeader() {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;
    final shortSide = size.shortestSide;

    bool isPhone = shortSide < 600;

    return Column(
      children: [
        SizedBox(height: 10),
        Row(
          children: [
            SizedBox(width: 20),
            mainCover(isPhone ? 120 : 160),
            Expanded(
              child: ListTile(
                title: AutoSizeText(
                  getTitleText(l10n),
                  maxLines: 1,
                  minFontSize: 20,
                  maxFontSize: 20,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: ValueListenableBuilder(
                  valueListenable: currentSongListNotifier,
                  builder: (context, currentSongList, child) {
                    String prefix = getSourceTypeDisplayName(l10n, sourceType);
                    return Text(
                      "$prefix: ${l10n.songCount(currentSongList.length)}",
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget pageContent() {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(child: pageHeader()),
        ValueListenableBuilder(
          valueListenable: currentSongListNotifier,
          builder: (context, currentSongList, child) {
            if (prepareing) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: iconColor.value),
                ),
              );
            }
            return SliverFixedExtentList.builder(
              itemExtent: 60,
              itemCount: currentSongList.length,
              itemBuilder: (context, index) {
                return Center(child: songListTile(index, currentSongList));
              },
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }

  Widget songListTile(int index, List<MyAudioMetadata> currentSongList) {
    final song = currentSongList[index];
    return ValueListenableBuilder(
      valueListenable: song.updateNotifier,
      builder: (context, value, child) {
        return ListTile(
          contentPadding: EdgeInsets.fromLTRB(20, 0, 0, 0),
          leading: CoverArtWidget(
            size: 40,
            borderRadius: 4,
            picture: song.picture,
          ),
          title: ValueListenableBuilder(
            valueListenable: currentSongNotifier,
            builder: (_, currentSong, _) {
              return ValueListenableBuilder(
                valueListenable: highlightTextColor.valueNotifier,
                builder: (context, value, child) {
                  return Text(
                    getTitle(song),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: song == currentSong ? value : null,
                      fontWeight: song == currentSong ? FontWeight.bold : null,
                    ),
                  );
                },
              );
            },
          ),

          subtitle: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: song.isFavoriteNotifier,
                builder: (_, value, _) {
                  return value
                      ? SizedBox(
                          width: 20,
                          child: Icon(
                            Icons.star_rounded,
                            color: Colors.red,
                            size: 15,
                          ),
                        )
                      : SizedBox();
                },
              ),
              Expanded(
                child: Text(
                  "${getArtist(song)} - ${getAlbum(song)}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
          onTap: () =>
              audioHandler.setPlayQueue(currentSongList, 0, targetIndex: index),
          trailing: isFrequently && sourceType != .emby
              ? SizedBox(
                  width: 100,
                  child: Row(
                    children: [
                      Spacer(),
                      ImageIcon(playOutlinedImage, size: 15),
                      Text(song.playCount.toString()),
                      songOptionsButton(index, song),
                    ],
                  ),
                )
              : songOptionsButton(index, song),
        );
      },
    );
  }

  Widget optionItem({
    required String text,
    required Icon leading,
    required Function() onTap,
  }) {
    return ListTile(
      leading: leading,
      title: Text(text),
      minTileHeight: 56,
      onTap: onTap,
    );
  }

  Widget songOptionsButton(int index, MyAudioMetadata song) {
    final l10n = AppLocalizations.of(context);

    return IconButton(
      icon: Icon(Icons.more_vert, size: 15),
      onPressed: () {
        tryVibrate();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (context) {
            return MySheet(
              Column(
                children: [
                  // a hint that the sheet can be dragged down
                  ValueListenableBuilder(
                    valueListenable: dividerColor.valueNotifier,
                    builder: (context, value, child) {
                      return Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        decoration: BoxDecoration(
                          color: value,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: CoverArtWidget(
                      size: 50,
                      borderRadius: 5,
                      picture: song.picture,
                    ),
                    title: Text(
                      getTitle(song),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      "${getArtist(song)} - ${getAlbum(song)}",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  SizedBox(height: 5),
                  MyDivider(color: dividerColor, thickness: 0.5, height: 1),
                  SizedBox(height: 5),

                  Expanded(
                    child: ListView(
                      physics: const ClampingScrollPhysics(),
                      children: [
                        if (reorderable)
                          optionItem(
                            text: l10n.move2Top,
                            leading: Icon(Icons.vertical_align_top_rounded),
                            onTap: () {
                              Navigator.pop(context);
                              moveToTop(index);
                            },
                          ),

                        optionItem(
                          text: l10n.playNow,
                          leading: Icon(Icons.play_arrow_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            audioHandler.singlePlay(song);
                            audioHandler.saveAllStates();
                          },
                        ),

                        optionItem(
                          text: l10n.playNext,
                          leading: Icon(Icons.navigate_next_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            if (playQueue.isEmpty) {
                              audioHandler.singlePlay(song);
                            } else {
                              audioHandler.insert2Next(song);
                            }
                            audioHandler.saveAllStates();
                          },
                        ),

                        optionItem(
                          text: l10n.add2Queue,
                          leading: Icon(Icons.playlist_add_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            if (playQueue.isEmpty) {
                              audioHandler.singlePlay(song);
                            } else {
                              audioHandler.add2Last(song);
                            }
                            audioHandler.saveAllStates();
                          },
                        ),

                        optionItem(
                          text: l10n.add2Playlist,
                          leading: Icon(Icons.add_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            showAddPlaylistDialog(context, [song]);
                          },
                        ),

                        if (artist == null)
                          optionItem(
                            text: l10n.go2Artist,
                            leading: Icon(Icons.people),
                            onTap: () {
                              Navigator.pop(context);
                              goToArtist(song, context);
                            },
                          )
                        else if (artist!.name != song.artist)
                          optionItem(
                            text: l10n.go2Artist,
                            leading: Icon(Icons.people),
                            onTap: () {
                              Navigator.pop(context);
                              goToArtist(
                                song,
                                context,
                                excludedArtist: artist!.name,
                              );
                            },
                          ),

                        if (album == null)
                          optionItem(
                            text: l10n.go2Album,
                            leading: Icon(Icons.album_rounded),
                            onTap: () {
                              Navigator.pop(context);
                              goToAlbum(song);
                            },
                          ),

                        optionItem(
                          text: l10n.songInfo,
                          leading: Icon(Icons.info_outline_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            showAnimationDialog(
                              context: context,
                              child: SongInfo(song: song),
                            );
                          },
                        ),

                        if (sourceType == .local &&
                            artist == null &&
                            album == null)
                          optionItem(
                            text: l10n.editMetadata,
                            leading: Icon(Icons.edit_rounded),
                            onTap: () {
                              Navigator.pop(context);
                              showAnimationDialog(
                                context: context,
                                child: EditMetadata(song: song),
                              );
                            },
                          ),

                        if (playlist != null)
                          optionItem(
                            text: l10n.delete,
                            leading: Icon(Icons.delete_rounded),
                            onTap: () async {
                              if (await showConfirmDialog(
                                context,
                                l10n.delete,
                              )) {
                                playlist!.remove([song]);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              }
                            },
                          ),

                        SizedBox(height: 50),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

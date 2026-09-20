part of '../../base/widgets/song_list.dart';

/// 双列布局下左右两格之间的间距。
const double _columnGap = 20;

/// 一个格子的各列宽度，以及是否显示专辑列。
typedef _SongColumns = ({
  double index,
  double star,
  double duration,
  bool album,
});

/// 按单个格子的可用宽度推导列宽：太窄就不要专辑列了，否则歌名会被挤没。
/// 表头与单元格共用同一份结果，保证对齐。
_SongColumns _songColumns(double cellWidth) {
  final narrow = cellWidth < 420;
  return (
    index: narrow ? 40 : 60,
    star: narrow ? 45 : 60,
    duration: narrow ? 60 : 80,
    album: !narrow,
  );
}

extension _SongListPanel on _SongListState {
  Widget panelView(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Opacity(
          opacity: hideOthers ? 0 : 1,
          child: TitleBar(
            hintText: l10n.searchSongs,
            textController: textController,
            backToRoot: backToRoot,
            scrollToTop: () {
              scrollController.animateTo(
                0,
                duration: Duration(milliseconds: 250),
                curve: Curves.linear,
              );
            },
            findLocation: () {
              if (currentSongNotifier.value == null) {
                return;
              }
              final index = currentSongListNotifier.value.indexWhere(
                (e) => currentSongNotifier.value!.id == e.id,
              );
              if (index == -1) {
                showCenterMessage('Current song not found');
                return;
              }
              final position = scrollController.position;
              final maxScrollExtent = position.maxScrollExtent;
              final minScrollExtent = position.minScrollExtent;
              // 双列后行号是 index ~/ 2；表头去掉后列表整体上移 50，故为 305
              scrollController.animateTo(
                (60 * (index ~/ 2) + 305 - (MediaQuery.heightOf(context) / 2))
                    .clamp(minScrollExtent, maxScrollExtent),
                duration: Duration(milliseconds: 250),
                curve: Curves.linear,
              );
            },
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) =>
                panelContent(context, constraints.maxWidth),
          ),
        ),
      ],
    );
  }

  Widget panelContent(BuildContext context, double maxWidth) {
    // 一行两首，格子宽度要扣掉左右 padding 和中间的列间距
    final columns = _songColumns(
      (maxWidth - padding.horizontal - _columnGap) / 2,
    );
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(padding: padding, child: panelHeader()),
        ),

        SliverPadding(
          padding: padding,
          sliver: ValueListenableBuilder(
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
              return SliverReorderableList(
                itemExtent: 60,
                itemBuilder: (context, row) {
                  if (hideOthers) {
                    return SizedBox(key: ValueKey(row));
                  }
                  final left = row * 2;
                  final right = left + 1;
                  return ReorderableDragStartListener(
                    key: ValueKey(currentSongList[left]),
                    enabled: !isFixed & canModify,
                    index: row,
                    child: Row(
                      children: [
                        Expanded(child: songListItem(left, columns)),
                        SizedBox(width: _columnGap),
                        Expanded(
                          child: right < currentSongList.length
                              ? songListItem(right, columns)
                              : SizedBox(),
                        ),
                      ],
                    ),
                  );
                },
                itemCount: (currentSongList.length + 1) ~/ 2,
                // 一行两首，一次拖动移动的是相邻的两首。框架给的 newIndex 已经
                // 修正过“移除后的位移”，所以直接 remove + insert 即可。
                onReorderItem: (oldRow, newRow) {
                  final start = oldRow * 2;
                  final moved = songList.sublist(
                    start,
                    min(start + 2, songList.length),
                  );
                  songList.removeRange(start, start + moved.length);
                  songList.insertAll(min(newRow * 2, songList.length), moved);

                  if (isLibrary) {
                    library.update();
                  } else if (folder != null) {
                    folder!.update();
                  } else {
                    playlist!.update();
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget panelHeader() {
    final l10n = AppLocalizations.of(context);

    final size = MediaQuery.of(context).size;
    final shortSide = size.shortestSide;

    bool isPhone = shortSide < 600;

    return SizedBox(
      height: isPhone ? 160 : 200,
      child: Row(
        children: [
          mainCover(isPhone ? 120 : 160),
          if (!hideOthers) SizedBox(width: 10),
          if (!hideOthers)
            Expanded(
              child: Column(
                children: [
                  SizedBox(height: isPhone ? 15 : 30),
                  ListTile(
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
                        String prefix = getSourceTypeDisplayName(
                          l10n,
                          sourceType,
                        );
                        return Text(
                          "$prefix: ${l10n.songCount(currentSongList.length)}",
                        );
                      },
                    ),
                  ),
                  Spacer(),

                  ListenableBuilder(
                    listenable: Listenable.merge([buttonColor.valueNotifier]),
                    builder: (_, _) {
                      final buttonStyle = ElevatedButton.styleFrom(
                        backgroundColor: buttonColor.value,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: EdgeInsets.all(10),
                      );
                      return SizedBox(
                        height: isMobile ? 40 : 35,
                        child: ListView(
                          scrollDirection: .horizontal,
                          children: [
                            SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                if (currentSongListNotifier.value.isEmpty) {
                                  return;
                                }
                                audioHandler.setPlayQueue(
                                  currentSongListNotifier.value,
                                  0,
                                );
                              },
                              style: buttonStyle,
                              child: Text(l10n.playAll),
                            ),

                            SizedBox(width: 15),
                            ElevatedButton(
                              onPressed: () {
                                if (currentSongListNotifier.value.isEmpty) {
                                  return;
                                }

                                audioHandler.setPlayQueue(
                                  currentSongListNotifier.value,
                                  1,
                                );
                              },
                              style: buttonStyle,
                              child: Text(l10n.shuffle),
                            ),

                            if (isMobile) ...[
                              SizedBox(width: 15),
                              ElevatedButton(
                                onPressed: () {
                                  for (var e in isSelectedNotifierMap.values) {
                                    e.value = false;
                                  }
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).push(
                                    MaterialPageRoute(
                                      builder: (_) => ValueListenableBuilder(
                                        valueListenable:
                                            currentSongListNotifier,
                                        builder:
                                            (context, currentSongList, child) {
                                              return SelectableSongListPage(
                                                songList: currentSongList,
                                                playlist: playlist,
                                                folder: folder,
                                                isFrequently: isFrequently,
                                                isRecently: isRecently,
                                                isLibrary: isLibrary,
                                                reorderable: reorderable,
                                                isSelectedNotifierMap:
                                                    isSelectedNotifierMap,
                                              );
                                            },
                                      ),
                                    ),
                                  );
                                },
                                style: buttonStyle,
                                child: Text(l10n.select),
                              ),
                            ],

                            // 表头去掉后，横屏排序统一复用竖屏顶栏那份完整菜单
                            if (!isFrequently && !isRecently) ...[
                              SizedBox(width: 15),
                              sortButton(context),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: isPhone ? 20 : 30),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget songListItem(int index, _SongColumns columns) {
    final currentSongList = currentSongListNotifier.value;
    final song = currentSongList[index];
    final isSelectedNotifier = isSelectedNotifierMap[song]!;
    final showPlayButtonNotifier = showPlayButtonNotifierMap[song]!;
    return ValueListenableBuilder(
      valueListenable: isSelectedNotifier,
      builder: (context, value, child) {
        return ValueListenableBuilder(
          valueListenable: selectedItemColor.valueNotifier,
          builder: (context, color, _) {
            return Material(
              color: value ? color : Colors.transparent,
              shape: SmoothRectangleBorder(
                smoothness: 1,
                borderRadius: .circular(10),
              ),
              clipBehavior: .antiAlias,
              child: child,
            );
          },
        );
      },
      child: MouseRegion(
        onEnter: (event) {
          showPlayButtonNotifier.value = true;
        },
        onExit: (event) {
          showPlayButtonNotifier.value = false;
        },
        child: Builder(
          builder: (context) {
            return GestureDetector(
              child: InkWell(
                child: ValueListenableBuilder(
                  valueListenable: song.updateNotifier,
                  builder: (_, _, _) {
                    return Row(
                      children: [
                        SizedBox(
                          width: columns.index,
                          child: Center(
                            child: indexOrIcon(
                              showPlayButtonNotifier,
                              index,
                              song,
                            ),
                          ),
                        ),

                        Expanded(flex: 4, child: mainInfo(song)),

                        SizedBox(width: 10),

                        if (columns.album)
                          Expanded(
                            flex: 3,
                            child: Text(
                              getAlbum(song),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                        SizedBox(
                          width: columns.star,
                          child: Center(
                            child: IconButton(
                              onPressed: () {
                                toggleFavoriteState(song);
                              },
                              icon: ValueListenableBuilder(
                                valueListenable: song.isFavoriteNotifier,
                                builder: (context, value, child) {
                                  return value
                                      ? Icon(
                                          Icons.star_rounded,
                                          color: Colors.red,
                                          size: 22,
                                        )
                                      : Icon(
                                          Icons.star_outline_rounded,
                                          size: 22,
                                        );
                                },
                              ),
                            ),
                          ),
                        ),

                        SizedBox(
                          width: columns.duration,
                          child: Text(
                            formatDuration(getDuration(song)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        if (widget.isFrequently && sourceType != .emby)
                          SizedBox(
                            width: 50,
                            child: Text(
                              song.playCount.toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                onTap: () async {
                  if (ctrlIsPressed) {
                    isSelectedNotifier.value = !isSelectedNotifier.value;
                    continuousSelectBeginIndex = index;
                  } else if (shiftIsPressed) {
                    int left = continuousSelectBeginIndex < index
                        ? continuousSelectBeginIndex
                        : index;
                    int right = continuousSelectBeginIndex > index
                        ? continuousSelectBeginIndex
                        : index;

                    for (int i = 0; i < currentSongList.length; i++) {
                      final song = currentSongList[i];
                      if (i < left || i > right) {
                        isSelectedNotifierMap[song]!.value = false;
                      } else {
                        isSelectedNotifierMap[song]!.value = true;
                      }
                    }
                  } else {
                    // clear select
                    for (var tmp in isSelectedNotifierMap.values) {
                      tmp.value = false;
                    }
                    isSelectedNotifier.value = true;
                    continuousSelectBeginIndex = index;
                  }

                  if (isMobile || waitForSecondClick) {
                    waitForSecondClick = false;
                    doubleClicktimer?.cancel();
                    await audioHandler.setPlayQueue(
                      currentSongList,
                      0,
                      targetIndex: index,
                    );
                  } else {
                    doubleClicktimer = Timer(Duration(milliseconds: 250), () {
                      waitForSecondClick = false;
                    });
                    waitForSecondClick = true;
                  }
                },
                onSecondaryTapUp: (details) {
                  popContextMenu(context, index, details.globalPosition);
                },
              ),
              onTapDown: (details) {
                if (Platform.isIOS) {
                  popContextMenu(context, index, details.globalPosition);
                }
              },
              onLongPressStart: (details) {
                if (Platform.isAndroid) {
                  tryVibrate();
                  popContextMenu(context, index, details.globalPosition);
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget indexOrIcon(
    ValueNotifier<bool> showPlayButtonNotifier,
    int index,
    MyAudioMetadata song,
  ) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (context, currentSong, child) {
        if (currentSong == song) {
          return ListenableBuilder(
            listenable: Listenable.merge([
              isPlayingNotifier,
              iconColor.valueNotifier,
            ]),
            builder: (context, child) {
              return PlayingBarsIcon(
                playing: isPlayingNotifier.value,
                color: iconColor.value,
                size: 30,
              );
            },
          );
        }
        return ValueListenableBuilder(
          valueListenable: showPlayButtonNotifier,
          builder: (context, value, child) {
            return value
                ? IconButton(
                    onPressed: () {
                      audioHandler.singlePlay(song);
                      audioHandler.saveAllStates();
                    },
                    icon: Icon(Icons.play_arrow_rounded),
                  )
                : Text((index + 1).toString(), overflow: TextOverflow.ellipsis);
          },
        );
      },
    );
  }

  Widget mainInfo(MyAudioMetadata song) {
    return ListTile(
      contentPadding: .zero,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      leading: CoverArtWidget(size: 40, borderRadius: 4, picture: song.picture),
      title: Text(
        getTitle(song),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        getArtist(song),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12),
      ),
    );
  }

  void popContextMenu(BuildContext context, int index, Offset globalPosition) {
    final currentSongList = currentSongListNotifier.value;
    final isSelectedNotifier = isSelectedNotifierMap[currentSongList[index]]!;
    // select current and clear others if it's not selected
    if (!isSelectedNotifier.value) {
      for (var tmp in isSelectedNotifierMap.values) {
        tmp.value = false;
      }
      isSelectedNotifier.value = true;
      continuousSelectBeginIndex = index;
    }

    final selectedSongList = <MyAudioMetadata>[];

    for (int i = 0; i < currentSongList.length; i++) {
      final song = currentSongList[i];

      if (isSelectedNotifierMap[song]!.value) {
        selectedSongList.add(song);
      }
    }

    final l10n = AppLocalizations.of(context);
    List<MenuItem> menuItems = [];

    if (selectedSongList.length == 1 && reorderable) {
      menuItems.add(
        MenuItem(
          iconData: Icons.vertical_align_top_rounded,
          text: l10n.move2Top,
          callback: () => moveToTop(index),
        ),
      );
    }
    menuItems.add(
      MenuItem(
        iconData: Icons.play_arrow_rounded,
        text: l10n.playNow,
        callback: () async {
          MyAudioMetadata? tmp;
          for (int i = selectedSongList.length - 1; i >= 0; i--) {
            tmp = selectedSongList[i];
            audioHandler.insert2Next(tmp);
          }

          if (tmp != currentSongNotifier.value) {
            await audioHandler.skipToNext();
          }
          audioHandler.play();
          audioHandler.saveAllStates();
        },
      ),
    );

    menuItems.add(
      MenuItem(
        iconData: Icons.navigate_next_rounded,
        text: l10n.playNext,
        callback: () async {
          for (int i = selectedSongList.length - 1; i >= 0; i--) {
            audioHandler.insert2Next(selectedSongList[i]);
          }

          if (audioHandler.currentIndex == -1) {
            await audioHandler.skipToNext();
            audioHandler.play();
          }
          audioHandler.saveAllStates();
        },
      ),
    );

    menuItems.add(
      MenuItem(
        text: l10n.add2Queue,
        iconData: Icons.playlist_add_rounded,
        callback: () async {
          for (int i = 0; i < selectedSongList.length; i++) {
            audioHandler.add2Last(selectedSongList[i]);
          }

          if (audioHandler.currentIndex == -1) {
            await audioHandler.skipToNext();
            audioHandler.play();
          }
          audioHandler.saveAllStates();
        },
      ),
    );

    menuItems.add(
      MenuItem(
        text: l10n.add2Playlist,
        iconData: Icons.add_rounded,
        callback: () {
          showAddPlaylistDialog(context, selectedSongList.reversed.toList());
        },
      ),
    );

    menuItems.add(MenuItem(isDivider: true));

    if (selectedSongList.length == 1) {
      final song = selectedSongList.first;
      if (artist == null) {
        menuItems.add(
          MenuItem(
            text: l10n.go2Artist,
            iconData: Icons.people,
            callback: () => goToArtist(song, context),
          ),
        );
      } else if (artist!.name != song.artist) {
        menuItems.add(
          MenuItem(
            text: l10n.go2Artist,
            iconData: Icons.people,
            callback: () =>
                goToArtist(song, context, excludedArtist: artist!.name),
          ),
        );
      }

      if (album == null) {
        menuItems.add(
          MenuItem(
            text: l10n.go2Album,
            iconData: Icons.album_rounded,
            callback: () => goToAlbum(song),
          ),
        );
      }

      menuItems.add(
        MenuItem(
          text: l10n.songInfo,
          iconData: Icons.info_outline_rounded,
          callback: () {
            showAnimationDialog(
              context: context,
              child: SongInfo(song: song),
            );
          },
        ),
      );

      if (sourceType == .local && artist == null && album == null) {
        menuItems.add(
          MenuItem(
            iconData: Icons.edit_rounded,
            text: l10n.editMetadata,
            callback: () {
              showAnimationDialog(
                context: context,
                child: EditMetadata(song: song),
              );
            },
          ),
        );
      }
    }

    if (playlist != null) {
      menuItems.add(
        MenuItem(
          text: l10n.delete,
          iconData: Icons.delete_rounded,
          callback: () async {
            if (await showConfirmDialog(context, l10n.delete)) {
              playlist!.remove(selectedSongList);
            }
          },
        ),
      );
    }

    if (menuItems.last.isDivider) {
      menuItems.removeLast();
    }

    showContextMenu(context, menuItems, globalPosition);
  }
}

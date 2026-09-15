part of "../../base/widgets/collection_list.dart";

extension _CollectionListPage on CollectionListState {
  Widget pageView(BuildContext context) {
    // the portrait home draws the one top bar and the tab bar, so this page
    // only publishes what goes in that top bar
    return rootTabContent(
      context,
      [
        searchField(searchHint),
        ListenableBuilder(
          listenable: Listenable.merge([
            isListViewNotifier,
            useLargePictureNotifier,
          ]),
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isListViewNotifier != null) viewButton(context),
                if (!(isListViewNotifier?.value ?? false))
                  pictureSizeButton(context),
                if (randomizeNotifier != null || isAscendingNotifier != null)
                  sortButton(context),
              ],
            );
          },
        ),
        moreButton(context),
      ],
      // its own Scaffold only to keep the floating action button (playlists)
      // where it used to be
      Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        floatingActionButton: floatingActionButton(context),
        body: ListenableBuilder(
          listenable: Listenable.merge([isListViewNotifier, changeNotifier]),
          builder: (context, child) {
            if (preparing) {
              return Center(
                child: CircularProgressIndicator(color: iconColor.value),
              );
            }
            return (isListViewNotifier?.value ?? false)
                ? listView()
                : pageGridView();
          },
        ),
      ),
    );
  }

  Widget searchField(String hintText) {
    return MySearchField(
      hintText: hintText,
      textController: textController,
      onSearchTextChanged: updateCurrentList,
    );
  }

  Widget viewButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IconButton(
      tooltip: l10n.view,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: ImageIcon(isListViewNotifier!.value ? listImage : gridImage),
      onPressed: () {
        tryVibrate();
        isListViewNotifier!.value = !isListViewNotifier!.value;
        setting.save();
      },
    );
  }

  Widget pictureSizeButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IconButton(
      tooltip: l10n.pictureSize,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: ImageIcon(pictureImage),
      onPressed: () {
        tryVibrate();
        useLargePictureNotifier.value = !useLargePictureNotifier.value;
        setting.save();
      },
    );
  }

  Widget sortButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Builder(
      builder: (buttonContext) {
        return IconButton(
          tooltip: l10n.order,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: ImageIcon(sequenceImage),
          onPressed: () {
            tryVibrate();

            final items = <MenuItem>[];

            if (randomizeNotifier != null) {
              items.add(
                MenuItem(
                  iconData: Icons.shuffle_rounded,
                  text: l10n.randomize,
                  callback: () {
                    if (randomizeNotifier!.value) {
                      return;
                    }
                    randomizeNotifier!.value = true;
                    updateCurrentList();
                  },
                ),
              );
            }

            if (isAscendingNotifier != null) {
              void selectAscending(bool value) {
                final wasRandom = randomizeNotifier?.value ?? false;
                if (randomizeNotifier != null) {
                  randomizeNotifier!.value = false;
                }
                if (isAscendingNotifier!.value != value) {
                  isAscendingNotifier!.value = value;
                } else if (wasRandom) {
                  updateCurrentList();
                }
                setting.save();
              }

              items.add(
                MenuItem(
                  iconData: Icons.arrow_upward_rounded,
                  text: l10n.ascending,
                  callback: () => selectAscending(true),
                ),
              );
              items.add(
                MenuItem(
                  iconData: Icons.arrow_downward_rounded,
                  text: l10n.descending,
                  callback: () => selectAscending(false),
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

  Widget listView() {
    return ListView.builder(
      itemExtent: 64,
      itemCount: currentPictureList.length,
      itemBuilder: (context, index) {
        final picture = currentPictureList[index];
        final text = currentTextList[index];
        return Center(
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 20),

            leading: Hero(
              tag: (picture?.id ?? '') + label + text,
              transitionOnUserGestures: true,
              child: CoverArtWidget(
                size: 50,
                borderRadius: 5,
                picture: picture,
              ),
            ),
            title: Text(text, style: .new(overflow: .ellipsis)),
            subtitle: currentSubCountList == null
                ? null
                : Text(
                    AppLocalizations.of(
                      context,
                    ).songCount(currentSubCountList![index]),
                  ),
            onTap: () {
              currentOnTapList[index].call();
            },
          ),
        );
      },
    );
  }

  Widget pageGridView() {
    return ValueListenableBuilder(
      valueListenable: useLargePictureNotifier,
      builder: (context, useLargePicture, child) {
        return GridView.builder(
          padding: EdgeInsets.symmetric(horizontal: 20),
          gridDelegate: MyGirdDelegate(
            maxCrossAxisExtent: useLargePicture ? 180 : 120,
            crossAxisSpacing: 10,
            mainAxisSpacing: 5,
            textExtent: 25,
          ),
          itemCount: currentPictureList.length,
          itemBuilder: (context, index) {
            final picture = currentPictureList[index];
            final text = currentTextList[index];

            return LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    GestureDetector(
                      child: Hero(
                        tag: (picture?.id ?? '') + label + text,
                        transitionOnUserGestures: true,
                        child: CoverArtWidget(
                          size: constraints.maxWidth,
                          borderRadius: constraints.maxWidth / 10,
                          picture: picture,
                        ),
                      ),
                      onTap: () {
                        currentOnTapList[index].call();
                      },
                    ),
                    SizedBox(
                      width: constraints.maxWidth - 10,
                      child: Text(
                        text,
                        textAlign: .center,
                        style: TextStyle(overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

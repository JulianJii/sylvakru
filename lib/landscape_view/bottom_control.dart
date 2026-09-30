import 'package:material_ui/material_ui.dart';
import 'package:sylvakru/base/asset_images.dart';
import 'package:sylvakru/base/audio_handler.dart';
import 'package:sylvakru/base/services/color_manager.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/widgets/buttons.dart';
import 'package:sylvakru/base/widgets/cover_art_widget.dart';
import 'package:sylvakru/base/utils/dynamic_lyrics_page_route.dart';
import 'package:sylvakru/landscape_view/speaker.dart';
import 'package:sylvakru/landscape_view/volume_bar.dart';
import 'package:sylvakru/base/widgets/seekbar.dart';
import 'package:sylvakru/layer/lyrics_page_layer.dart';
import 'package:sylvakru/base/utils/metadata_utils.dart';
import 'package:smooth_corner/smooth_corner.dart';

class BottomControl extends StatelessWidget {
  const BottomControl({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: bottomColor.valueNotifier,
      builder: (context, value, child) {
        return Material(
          color: value,
          child: SizedBox(
            // 比按钮行高出的余量：进度条 20 + 播放/暂停按钮 66。
            height: 92,
            child: Row(
              children: [
                Expanded(flex: 2, child: currentSongTile(context)),

                if (isMobile) ...[
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: .center,
                      children: [...playControls(), SizedBox(width: 10)],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: EdgeInsets.only(right: 20),
                      child: bottomSeekBar(),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: 20),
                          child: Transform.translate(
                            offset: Offset(0, 6),
                            child: bottomSeekBar(),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: .center,
                          children: playControls(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(flex: 2, child: otherControls()),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget currentSongTile(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (_, currentSong, _) {
        return Theme(
          data: Theme.of(context).copyWith(
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: Material(
            color: Colors.transparent,
            shape: SmoothRectangleBorder(
              smoothness: 1,
              borderRadius: .all(.circular(10)),
            ),
            clipBehavior: .antiAlias,
            child: ListenableBuilder(
              listenable: Listenable.merge([currentSong?.updateNotifier]),
              builder: (context, _) {
                return ListTile(
                  leading: Hero(
                    tag: 'cover',
                    child: CoverArtWidget(
                      size: 50,
                      borderRadius: 5,
                      picture: currentSong?.picture,
                      useResize: false,
                    ),
                  ),
                  title: Text(
                    getTitle(currentSong),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: currentSong != null
                      ? Text(
                          "${getArtist(currentSong)} - ${getAlbum(currentSong)}",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13),
                        )
                      : null,
                  onTap: () {
                    if (playQueue.isEmpty) {
                      return;
                    }
                    Navigator.of(context, rootNavigator: true).push(
                      DynamicLyricsPageRoute(
                        pageBuilder: (_, _, _) => LyricsPageLayer(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget bottomSeekBar() {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (_, _, _) {
        return SeekBar(widgetHeight: 20, seekBarHeight: 10);
      },
    );
  }

  List<Widget> playControls() {
    return [
      playModeButton(40),

      skip2PreviousButton(40),

      playOrPauseButton(50),

      skip2NextButton(40),

      showPlayQueueButton(40),
    ];
  }

  Widget otherControls() {
    return Row(
      children: [
        Spacer(),
        ValueListenableBuilder(
          valueListenable: iconColor.valueNotifier,
          builder: (context, value, child) {
            return _VolumePopover(color: value);
          },
        ),
        SizedBox(width: 30),
      ],
    );
  }
}

class _VolumePopover extends StatelessWidget {
  const _VolumePopover({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: currentSongNotifier,
      builder: (context, _, _) {
        return MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(
              Color.alphaBlend(
                colorManager.getSpecificMenuColor(),
                colorManager.getSpecificBgBaseColor(),
              ),
            ),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            shape: WidgetStatePropertyAll(
              SmoothRectangleBorder(
                smoothness: 1,
                borderRadius: .circular(10),
              ),
            ),
            elevation: WidgetStatePropertyAll(6),
          ),
          builder: (context, controller, child) {
            return IconButton(
              color: color,
              icon: ValueListenableBuilder(
                valueListenable: volumeNotifier,
                builder: (_, volume, _) {
                  return ImageIcon(
                    volume == 0 ? speakerOffImage : speakerImage,
                    size: 32,
                  );
                },
              ),
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
            );
          },
          menuChildren: [
            SizedBox(
              width: 200,
              height: 48,
              child: Row(
                children: [
                  Speaker(color: color),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: volumeBarColor.valueNotifier,
                      builder: (context, value, child) {
                        return VolumeBar(activeColor: value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

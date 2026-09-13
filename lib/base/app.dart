import 'dart:io';

import 'package:material_ui/material_ui.dart';

const String versionNumber = '4.1.0';

late final Directory appDocsDir;
late final Directory appSupportDir;
late final Directory tmpDir;
String? iosFileProviderStorage;

final isMobile = Platform.isAndroid || Platform.isIOS;
const isTV = bool.fromEnvironment('TV', defaultValue: false);

final globalNavigatorKey = GlobalKey<NavigatorState>();

/// Corner radius applied to the lyrics page while it is being dragged down.
const double dragCornerRadius = 12;

enum ThemeType { vivid, light, dark, custom }

final mainPageThemeNotifier = ValueNotifier(ThemeType.vivid);
final lyricsPageThemeNotifier = ValueNotifier(ThemeType.vivid);

final ValueNotifier<Locale?> localeNotifier = ValueNotifier(null);

enum SourceType { local, webdav, navidrome, emby }

SourceType sourceType = .local;

bool isStreamSource = false;
bool isNotStreamSource = !isStreamSource;

final ValueNotifier<String?> fontFamilyNotifier = ValueNotifier(null);

final List<String> importedFonts = [];

enum ViewMode { normal, mini, bigPicture }

final viewModeNotifier = ValueNotifier(ViewMode.normal);

final immersiveWideLayoutNotifier = ValueNotifier(true);

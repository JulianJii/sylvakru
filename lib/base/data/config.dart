import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sylvakru/base/app.dart';
import 'package:sylvakru/base/services/emby_client.dart';
import 'package:sylvakru/base/services/feiniu_client.dart';
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/base/services/navidrome_client.dart';
import 'package:sylvakru/base/services/stream_client.dart';
import 'package:sylvakru/base/services/webdav_client.dart';

final config = Config();

class Config {
  late final File file;

  String? navidromeBaseUrl;
  String? navidromeUsername;
  String? navidromePassword;

  String? embyBaseUrl;
  String? embyUsername;
  String? embyPassword;

  String? feiniuBaseUrl;
  String? feiniuUsername;
  String? feiniuPassword;

  static const _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<void> load() async {
    file = File("${appSupportDir.path}/config.json");
    if (!(file.existsSync())) {
      return;
    }

    final content = await file.readAsString();

    final Map<String, dynamic> map =
        jsonDecode(content) as Map<String, dynamic>;

    final webdavMap = map['webdav'] as Map<String, dynamic>?;
    if (webdavMap != null) {
      String? securePassword = await _trySecureRead('webdav_password');
      securePassword ??= webdavMap['password'];
      securePassword ??= '';

      webdavClient = WebDavClient(
        baseUrl: webdavMap['baseUrl'],
        username: webdavMap['username'],
        password: securePassword,
      );
    }

    final navidromeMap = map['navidrome'] as Map<String, dynamic>?;
    if (navidromeMap != null) {
      navidromeBaseUrl = navidromeMap['baseUrl'];
      navidromeUsername = navidromeMap['username'];

      navidromePassword = await _trySecureRead('navidrome_password');
      navidromePassword ??= navidromeMap['password'];
      navidromePassword ??= '';
    }

    final embyMap = map['emby'] as Map<String, dynamic>?;
    if (embyMap != null) {
      embyBaseUrl = embyMap['baseUrl'];
      embyUsername = embyMap['username'];

      embyPassword = await _trySecureRead('emby_password');
      embyPassword ??= embyMap['password'];
      embyPassword ??= '';
    }

    final feiniuMap = map['feiniu'] as Map<String, dynamic>?;
    if (feiniuMap != null) {
      feiniuBaseUrl = feiniuMap['baseUrl'];
      feiniuUsername = feiniuMap['username'];

      feiniuPassword = await _trySecureRead('feiniu_password');
      feiniuPassword ??= feiniuMap['password'];
      feiniuPassword ??= '';
    }

    final tmpSourceType = map['sourceType'] as String?;
    if (tmpSourceType != null) {
      sourceType = SourceType.values.firstWhere((e) => e.name == tmpSourceType);
    } else {
      if (webdavClient != null) {
        sourceType = .webdav;
      } else if (navidromeMap != null) {
        sourceType = .navidrome;
      } else if (embyMap != null) {
        sourceType = .emby;
      } else if (feiniuMap != null) {
        sourceType = .feiniu;
      }
    }

    isStreamSource =
        sourceType == .navidrome ||
        sourceType == .emby ||
        sourceType == .feiniu;
    isNotStreamSource = !isStreamSource;

    if (sourceType == .navidrome && navidromeMap != null) {
      streamClient = NavidromeClient(
        baseUrl: navidromeBaseUrl!,
        username: navidromeUsername!,
        password: navidromePassword!,
      );
    } else if (sourceType == .emby && embyMap != null) {
      streamClient = EmbyClient(
        baseUrl: embyBaseUrl!,
        username: embyUsername!,
        password: embyPassword!,
      );
    } else if (sourceType == .feiniu && feiniuMap != null) {
      streamClient = FeiniuClient(
        baseUrl: feiniuBaseUrl!,
        username: feiniuUsername!,
        password: feiniuPassword!,
      );
    }

    if (_hasPlainTextPassword(map)) {
      await save();
    }
  }

  Future<void> save() async {
    // Secure storage (keyring/Keychain) can fail to write - e.g. no Secret
    // Service running on some Linux setups - and previously that failure was
    // silently ignored while the plaintext password was still stripped from
    // config.json, permanently losing the credential on the next load. Keep
    // the plaintext as a fallback in that one field until a write actually
    // succeeds, instead of losing it outright.
    bool webdavSecured = true;
    bool navidromeSecured = true;
    bool embySecured = true;
    bool feiniuSecured = true;

    if (webdavClient != null) {
      webdavSecured = await _trySecureWrite(
        'webdav_password',
        webdavClient!.password,
      );
    }

    if (navidromePassword != null) {
      navidromeSecured = await _trySecureWrite(
        'navidrome_password',
        navidromePassword!,
      );
    }

    if (embyPassword != null) {
      embySecured = await _trySecureWrite('emby_password', embyPassword!);
    }

    if (feiniuPassword != null) {
      feiniuSecured = await _trySecureWrite('feiniu_password', feiniuPassword!);
    }

    await file.writeAsString(
      jsonEncode({
        'sourceType': sourceType.name,

        if (webdavClient != null)
          'webdav': {
            'baseUrl': webdavClient!.baseUrl,
            'username': webdavClient!.username,
            if (!webdavSecured) 'password': webdavClient!.password,
          },

        if (navidromeBaseUrl != null)
          'navidrome': {
            'baseUrl': navidromeBaseUrl,
            'username': navidromeUsername,
            if (!navidromeSecured) 'password': navidromePassword,
          },

        if (embyBaseUrl != null)
          'emby': {
            'baseUrl': embyBaseUrl,
            'username': embyUsername,
            if (!embySecured) 'password': embyPassword,
          },

        if (feiniuBaseUrl != null)
          'feiniu': {
            'baseUrl': feiniuBaseUrl,
            'username': feiniuUsername,
            if (!feiniuSecured) 'password': feiniuPassword,
          },
      }),
    );
  }

  Future<String?> _trySecureRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      logger.output('Failed to read "$key" from secure storage: $e');
      return null;
    }
  }

  Future<bool> _trySecureWrite(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
      return true;
    } catch (e) {
      logger.output('Failed to write "$key" to secure storage: $e');
      return false;
    }
  }

  bool _hasPlainTextPassword(Map<String, dynamic> map) {
    for (var key in ['webdav', 'navidrome', 'emby', 'feiniu']) {
      if (map[key] != null && map[key]['password'] != null) {
        return true;
      }
    }
    return false;
  }
}

// 在线音乐新音源（kg/tx/wy）的签名与加密自检。
//
// zzcSign 的期望值由 lx-music-desktop 的原实现（tx/utils/crypto.js，node）
// 对同一文本算出；换签名算法或改 jsonEncode 的键序都会在这里失败。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/online_music/online_music_api.dart';

void main() {
  test('txZzcSign 与 lx 原实现（node）输出一致', () {
    final text = jsonEncode({
      'comm': {'ct': '19', 'cv': '2151'},
      'req': {
        'module': 'music.search.SearchCgiService',
        'method': 'DoSearchForQQMusicDesktop',
        'param': {'query': 'test'},
      },
    });
    expect(txZzcSign(text), 'zzc1f6977elkce8b8srapflkqt1a4kzc4ig7fc9e66d');
  });

  test('wyEapiParams 输出大写 hex 且按 16 字节分组对齐', () {
    final params = wyEapiParams('/api/search/song/list/page', {
      'keyword': '晴天',
      'limit': 30,
      'total': true,
    });
    expect(params, matches(RegExp(r'^[0-9A-F]+$')));
    expect(params.length % 32, 0);
  });

  test('wyLinuxParams 对同一输入输出稳定（ECB 确定性）', () {
    final object = {
      'method': 'POST',
      'url': 'https://music.163.com/api/v3/playlist/detail',
      'params': {'id': '123', 'n': 100000},
    };
    expect(wyLinuxParams(object), wyLinuxParams(object));
  });
}

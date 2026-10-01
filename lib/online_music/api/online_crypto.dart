// 第三方音源的签名/加密（QQ zzcSign、网易 eapi / linuxapi），
// 以及歌词与封面的解析规则。

import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

import 'package:sylvakru/online_music/api/online_http.dart';

/// QQ 音乐 `zzcSign`（lx `musicSdk/tx/utils/crypto.js`）：SHA1 按固定下标拆成
/// 前后两段，中段逐字节异或后 base64 去掉 `/\+=`，整体小写。
/// 注意 SHA1 hex 是 40 字符，前段下标 40 越界，lx 里 JS 取到 undefined
/// 拼接成空串——这里保持同口径。
String txZzcSign(String text) {
  const part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19];
  const part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5];
  const scrambleValues = [
    89, 39, 179, 150, 218, 82, 58, 252, 177, 52,
    186, 123, 120, 64, 242, 133, 143, 161, 121, 179,
  ];
  final hash = sha1.convert(utf8.encode(text)).toString();
  String pick(List<int> indexes) => [
    for (final index in indexes) index < hash.length ? hash[index] : '',
  ].join();
  final scrambled = [
    for (var i = 0; i < scrambleValues.length; i++)
      scrambleValues[i] ^ int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16),
  ];
  final b64 = base64.encode(scrambled).replaceAll(RegExp(r'[\\/+=]'), '');
  return 'zzc${pick(part1Indexes)}$b64${pick(part2Indexes)}'.toLowerCase();
}

/// AES-128-ECB（PKCS7），输出大写 hex。网易 eapi / linuxapi 共用。
String _aesEcbHexUpper(List<int> plain, String key) {
  final bytes =
      Encrypter(AES(Key.fromUtf8(key), mode: AESMode.ecb))
          .encryptBytes(plain)
          .bytes;
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

/// 网易 eapi（lx `musicSdk/wy/utils/crypto.js`）：请求体摘要拼进明文再整体
/// 加密，hex 大写后作为 form 的 `params` 字段。
String wyEapiParams(String url, Object data) {
  final text = jsonEncode(data);
  final digest = md5
      .convert(utf8.encode('nobody${url}use${text}md5forencrypt'))
      .toString();
  return _aesEcbHexUpper(
    utf8.encode('$url-36cd479b6b5-$text-36cd479b6b5-$digest'),
    'e82ckenh8dichen8',
  );
}

/// 网易 linuxapi：整个 `{method, url, params}` JSON 加密，form 字段是
/// `eparams`。响应是明文 JSON，无需解密（lx 请求层也不解）。
String wyLinuxParams(Object object) =>
    _aesEcbHexUpper(utf8.encode(jsonEncode(object)), 'rFgB&h#%2?^eDg:Q');

/// 酷我歌词接口的加密参数：明文循环异或固定密钥 `yeelion` 后 base64。
String kuwoLyricParam(String rid) {
  final plain = utf8.encode(
    'user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_$rid',
  );
  final key = utf8.encode('yeelion');
  return base64.encode([
    for (var i = 0; i < plain.length; i++) plain[i] ^ key[i % key.length],
  ]);
}

/// 酷我歌词响应体：`tp=content\r\n…\r\n\r\n` + zlib 压缩的 gb18030 文本。
/// 头部是 ASCII，用 latin1 逐字节对照字符串下标即可定位压缩数据。
String decodeKuwoLyricBody(List<int> body) {
  final text = latin1.decode(body);
  final offset = text.startsWith('tp=content') ? text.indexOf('\r\n\r\n') : -1;
  if (offset < 0) return '';
  return gbk.decode(zlib.decode(body.sublist(offset + 4)), allowMalformed: true);
}

/// 酷我封面接口（lx-music `musicSdk/kw/pic.js`）：响应体本身就是图片地址，
/// 没有封面时返回的是一句提示文本，不是 http 开头。
String parseKwPic(String body) {
  final text = body.trim();
  return text.startsWith('http') ? text : '';
}

/// 咪咕封面接口（lx-music `musicSdk/mg/pic.js`）：resourceinfo.do 返回的
/// `resource[].albumImgs[0].img`，相对路径补上 CDN 域名。
String parseMgPic(Object? resource) {
  for (final item in resource is List ? resource : const []) {
    final imgs = asMap(item)['albumImgs'];
    for (final img in imgs is List ? imgs : const []) {
      final url = '${asMap(img)['img'] ?? ''}';
      if (url.isEmpty) continue;
      return url.startsWith('http') ? url : 'http://d.musicapp.migu.cn$url';
    }
  }
  return '';
}

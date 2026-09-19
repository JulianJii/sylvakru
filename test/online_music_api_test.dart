// fetchScript 的入参校验 + 多脚本设置的落盘。
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/base/app.dart' as app;
import 'package:sylvakru/base/services/logger.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_bridge.dart';
import 'package:sylvakru/online_music/lx_js/lx_js_source.dart';
import 'package:sylvakru/online_music/online_music_api.dart';

void main() {
  // 服务端错误页正文是几千行样式，只有 <title> 说了发生了什么。
  test('失败原因取人话那一段', () {
    expect(
      lxFailureText(
        '<!DOCTYPE html>\n<html><head><title>Error 1027 | CF</title></head>'
        '<body>${'<script>x</script>' * 500}</body></html>',
      ),
      'Error 1027 | CF',
    );
    expect(lxFailureText('  error code: 1027  '), 'error code: 1027');
    expect(lxFailureText('x' * 200).length, 120);
  });

  // 野草源只给 128k：用户选 320k 时脚本返回空，得按从高到低退档再试。
  test('取链音质回退顺序', () {
    expect(qualityTries('320k', const ['128k']), ['320k', '128k']);
    expect(qualityTries('128k', const ['128k']), ['128k']);
    expect(
      qualityTries('flac', const ['128k', '320k', 'flac', 'flac24bit']),
      ['flac', 'flac24bit', '320k', '128k'],
    );
    // 不在 qualityOrder 里的音质排在最后。
    expect(qualityTries('320k', const ['ape', '128k']), ['320k', '128k', 'ape']);
  });

  // 脚本会拿 version 去服务端查配置、拿 rawScript 的 md5 自校验（grass 就是这样），
  // 所以头部注释必须解析出来，原文也必须原样带上。
  test('脚本元信息从头部注释解析', () {
    const script = '/**\n * @name 野草🌾\n * @version 1\n */\nconsole.log(1)';
    final meta = LxScriptMeta.fromScript(script, name: 'latest.js');
    expect(meta.name, '野草🌾');
    expect(meta.version, '1');
    expect(meta.rawScript, script);
    expect(meta.toJson()['rawScript'], script);

    const juhe = '/*!\n * @name 聚合API接口 (CF)\n * @description v3\n * @version 3\n */';
    final juheMeta = LxScriptMeta.fromScript(juhe, name: 'latest.js');
    expect(juheMeta.name, '聚合API接口 (CF)');
    expect(juheMeta.description, 'v3');
    expect(juheMeta.version, '3');

    // 没有头部注释：回落到导入时的名字。
    final plain = LxScriptMeta.fromScript('send("inited")', name: 'latest.js');
    expect(plain.name, 'latest.js');
    expect(plain.version, '1.0');
  });

  test('非 http(s) 链接被拒', () async {
    for (final url in ['ftp://x/a.js', '不是链接', '']) {
      await expectLater(
        onlineApiClient.fetchScript(url),
        throwsA(isA<OnlineApiException>()),
      );
    }
  });

  // 酷我歌词参数是「明文循环异或 yeelion 再 base64」，密钥/明文格式变了这里就挂。
  test('酷我歌词参数可用 yeelion 还原', () {
    final masked = base64.decode(kuwoLyricParam('65633689'));
    final key = utf8.encode('yeelion');
    final plain = String.fromCharCodes([
      for (var i = 0; i < masked.length; i++) masked[i] ^ key[i % key.length],
    ]);
    expect(
      plain,
      'user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_65633689',
    );
  });

  // 响应体是 `tp=content\r\n…\r\n\r\n` + zlib 压缩的 gb18030。
  test('酷我歌词响应体解压解码', () {
    final lrc = '[00:00.00]第一行\n[00:01.00]second';
    final body = <int>[
      ...utf8.encode('tp=content\r\npath=1\r\n\r\n'),
      ...zlib.encode(gbk.encode(lrc)),
    ];
    expect(decodeKuwoLyricBody(body), lrc);
    expect(decodeKuwoLyricBody(utf8.encode('not a lyric response')), '');
  });

  // 封面：两个音源的响应形状差得远，都按 lx-music 的 getPic 口径解。
  test('封面地址解析', () {
    // 酷我：响应体本身就是图片地址，没有封面时返回的是提示文本。
    expect(
      parseKwPic('http://img4.kuwo.cn/star/albumcover/500/a.jpg'),
      'http://img4.kuwo.cn/star/albumcover/500/a.jpg',
    );
    expect(parseKwPic('  https://img2.kuwo.cn/a.jpg \n'), 'https://img2.kuwo.cn/a.jpg');
    expect(parseKwPic(''), '');
    expect(parseKwPic('not found'), '');

    // 咪咕：resourceinfo.do 的 resource[].albumImgs[0].img，相对路径补 CDN 域名。
    expect(
      parseMgPic([
        {
          'albumImgs': [
            {'img': 'http://cdn.migu.cn/a.jpg'},
          ],
        },
      ]),
      'http://cdn.migu.cn/a.jpg',
    );
    expect(
      parseMgPic([
        {
          'albumImgs': [
            {'img': '/v1/pic/a.jpg'},
          ],
        },
      ]),
      'http://d.musicapp.migu.cn/v1/pic/a.jpg',
    );
    // 没有封面 / 响应不是预期结构：空串，UI 退占位图。
    expect(parseMgPic([{'albumImgs': []}]), '');
    expect(parseMgPic(const []), '');
    expect(parseMgPic(null), '');
    expect(parseMgPic('unexpected'), '');
  });

  // 多脚本列表：填写顺序就是取链优先级，同链接再导入是覆盖而不是新增，
  // 重启后顺序不变。
  test('脚本列表：顺序、去重、落盘恢复', () async {
    app.appSupportDir = await Directory.systemTemp.createTemp('online_settings');
    await logger.init();

    final settings = OnlineSettings();
    await settings.load();
    expect(settings.hasScript, isFalse);

    await settings.addScript(
      const LxScriptEntry(name: 'a.js', url: 'https://x/a.js', script: 'A'),
    );
    await settings.addScript(
      const LxScriptEntry(name: 'b.js', url: 'https://x/b.js', script: 'B'),
    );
    await settings.addScript(
      const LxScriptEntry(name: 'a2.js', url: 'https://x/a.js', script: 'A2'),
    );
    expect(settings.scripts.value.map((e) => e.name), ['a2.js', 'b.js']);

    final reloaded = OnlineSettings();
    await reloaded.load();
    expect(reloaded.scripts.value.map((e) => e.script), ['A2', 'B']);
    expect(reloaded.hasScript, isTrue);

    await reloaded.removeScript(0);
    expect(reloaded.scripts.value.map((e) => e.name), ['b.js']);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sylvakru/online_music/online_play_order.dart';

void main() {
  test('列表循环按顺序走，末尾回绕', () {
    expect(onlineNextIndex(1, 5, 0, 1), 2);
    expect(onlineNextIndex(4, 5, 0, 1), 0);
    expect(onlineNextIndex(0, 5, 0, -1), 4);
  });

  test('随机播放不选当前曲', () {
    for (var current = 0; current < 5; current++) {
      for (var random = 0; random < 4; random++) {
        expect(
          onlineNextIndex(current, 5, 1, 1, random: random),
          isNot(current),
        );
      }
    }
  });

  test('单首列表不越界', () {
    for (final mode in [0, 1, 2]) {
      expect(onlineNextIndex(0, 1, mode, 1), 0);
      expect(onlineNextIndex(0, 1, mode, -1), 0);
    }
  });

  test('单曲循环下手动切歌按顺序走', () {
    expect(onlineNextIndex(1, 3, 2, 1), 2);
    expect(onlineNextIndex(0, 3, 2, -1), 2);
  });
}

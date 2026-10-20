// 在线播放的换曲下标计算。
//
// 在线播放队列只放当前一首（直链按需解析），"下一首"要靠搜索结果/歌单
// 列表自己算，所以单独抽成纯函数，方便测试。

import 'dart:math';

/// 按播放模式算出 [current] 的下一个下标。
///
/// [mode]：0 列表循环 / 1 随机播放 / 2 单曲循环。
/// [delta]：1 下一首、-1 上一首。单曲循环的自动重播由播放器的 completed
/// 分支处理，走到这里的单曲循环只可能是手动切歌，按顺序走（与本地一致）。
/// [random]：测试用的随机数；生产路径不传，用 [Random] 现取。
int onlineNextIndex(
  int current,
  int length,
  int mode,
  int delta, {
  int? random,
}) {
  if (length <= 1) return 0;
  if (current < 0 || current >= length) current = 0;

  if (mode == 1) {
    // 在"除当前曲之外"的区间里取一个，保证不会切回自己。
    final pick = (random ?? Random().nextInt(length - 1)).abs() % (length - 1);
    return pick >= current ? pick + 1 : pick;
  }

  return (current + delta + length) % length;
}

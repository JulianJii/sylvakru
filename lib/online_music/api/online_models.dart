// 在线音乐的数据模型：接口异常、搜索结果与歌单结果。

/// 在线音乐接口抛出的业务异常。文案直接面向用户。
class OnlineApiException implements Exception {
  OnlineApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一条在线搜索结果。
///
/// 字段刻意保持 lx-music 的「旧格式 musicInfo」形状，[toMusicInfo] 才能原样
/// POST 给聚合接口 —— 服务端解析的就是这套字段。
class OnlineTrack {
  OnlineTrack({
    required this.source,
    required this.songmid,
    required this.name,
    required this.singer,
    required this.albumName,
    required this.albumId,
    required this.interval,
    required this.types,
    this.img,
    this.extra = const {},
  });

  final String source; // 'kw' | 'kg' | 'tx' | 'wy' | 'mg'
  final String songmid;
  final String name;
  final String singer;
  final String albumName;
  final String albumId;
  final String interval; // '04:29'

  /// 搜索结果自带的封面。酷我搜索不带，得由
  /// [OnlineApiClient.fetchPicUrl] 现取，所以这里允许为空。
  final String? img;

  /// `[{type: '320k', size: '8.1M'}]`
  final List<Map<String, String>> types;

  /// 源特有字段（mg 的 copyrightId / lrcUrl / mrcUrl / trcUrl）。
  final Map<String, dynamic> extra;

  /// 加 `online_` 前缀，避免和本地曲目 id 撞车。
  String get id => 'online_${source}_$songmid';

  List<String> get qualitys => types
      .map((type) => type['type'] ?? '')
      .where((type) => type.isNotEmpty)
      .toList();

  Map<String, dynamic> toMusicInfo() => {
    'name': name,
    'singer': singer,
    'source': source,
    'songmid': songmid,
    'interval': interval,
    'albumName': albumName,
    'img': img ?? '',
    'typeUrl': <String, dynamic>{},
    'albumId': albumId,
    'types': types,
    '_types': {
      for (final type in types)
        type['type']!: {'size': type['size'] ?? ''},
    },
    ...extra,
  };
}

/// 一条在线歌单搜索结果。
class OnlinePlaylist {
  OnlinePlaylist({
    required this.source,
    required this.id,
    required this.name,
    required this.creator,
    required this.pic,
    required this.songCount,
    required this.playCount,
    this.intro,
  });

  final String source; // 'kw' | 'kg' | 'tx' | 'wy' | 'mg'
  final String id;
  final String name;
  final String creator;
  final String pic;
  final int songCount;
  final int playCount;
  final String? intro;

  String get songCountFormatted => '$songCount 首';

  String get playCountFormatted {
    if (playCount >= 100000000) {
      return '${(playCount / 100000000).toStringAsFixed(1)}亿播放';
    }
    if (playCount >= 10000) {
      return '${(playCount / 10000).toStringAsFixed(1)}万播放';
    }
    if (playCount > 0) return '$playCount 播放';
    return '';
  }
}

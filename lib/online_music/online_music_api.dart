// 在线音乐模块的公开入口（barrel）。
//
// 实现按职责拆在 api/ 下：HTTP 通道与解析工具、数据模型、签名/加密、
// 本地设置、音源接口与注册表、5 个音源、直链解析客户端。
// 保留本文件是为了让既有的 `online_music_api.dart` 导入路径继续可用。

export 'api/online_api_client.dart';
export 'api/online_crypto.dart';
export 'api/online_http.dart';
export 'api/online_models.dart';
export 'api/online_searcher.dart';
export 'api/online_settings.dart';
export 'api/searchers/kg_searcher.dart';
export 'api/searchers/kw_searcher.dart';
export 'api/searchers/mg_searcher.dart';
export 'api/searchers/tx_searcher.dart';
export 'api/searchers/wy_searcher.dart';

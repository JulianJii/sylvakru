# SylvaKru自用修改版

跨平台音乐播放器，分叉自 [AfalpHy/sylvakru](https://github.com/AfalpHy/sylvakru)。完整功能与构建说明见上游 README，本文件只记录本分支相对上游的改动。

## 本分支改动

- **精简体积**：自绘 `playing_bars_icon.dart` 替换 Rive 图标（移除 `rive_animated_icons`）；移除 `screen_corner_radius`（歌词下拉改用常量 `dragCornerRadius = 12`）及 `flex_color_picker`、`google_fonts` 等无用依赖；应用图标 1.7MB → 0.48MB。
- **竖屏导航重构**：移除侧边抽屉，改用 `root_tab_bar.dart` 底部标签栏（最多播放 / 最近 / 歌曲 / 歌单 / 艺术家 / 专辑 / 文件夹），支持长按/拖拽排序并持久化到 `setting.json`；新增公共 `MyAppBar` / `MyAppBar.detail()`；设置页改为可返回路由而非切换 root layer。
- **体验修复**：修复横屏超出像素、播放页点击封面缩小动画。
- **独立网络音乐模块**
- **构建/发布**：Android 启用 `useLegacyPackaging` 压缩（arm64 APK 约 53.6MB → 27MB）；`AudioService` 增加 `MediaBrowserService` intent-filter；新增 GitHub Actions 发布工作流 `.github/workflows/release.yml`（构建 Flutter 版本需与 `pubspec.yaml` / `.fvmrc` 保持一致）。

## 上游版本

已同步上游 4.3.0（Flutter 3.47.5，`upstream-repo/main` 的 `3e44f4b`）：

- 新增首页层（`home_layer.dart`），桌面端支持鼠标滚动
- 飞牛 / Emby 播放历史
- 飞牛支持 FN ID 与 NAS 授权登录：地址栏可直接填 FN ID（自动展开为 `https://<id>.fnos.net` 并走 relay），令牌存安全存储；新增 `webview_flutter` 依赖，授权入口仅 Android / iOS / macOS 显示
- 原“排行”改名为“最多播放”
- Android 播放修复：media-kit 切到 openssl 构建（`AfalpHy/media-kit` git 依赖，见 `pubspec.yaml` 的 `dependency_overrides`；具体 commit 以 `pubspec.lock` 的 `resolved-ref` 为准）
- 其它修复：Emby 未登录时播放失败、首次同步与收藏加载、竖屏歌词页小尺寸截断、大图模式歌单封面 180 → 240、文件夹入口仅非流媒体源显示、开启启动自动播放时无法进入歌词页

## 许可证

见 `LICENSE`。

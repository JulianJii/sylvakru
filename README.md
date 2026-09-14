# SylvaKru自用修改版

跨平台音乐播放器，分叉自 [AfalpHy/sylvakru](https://github.com/AfalpHy/sylvakru)。完整功能与构建说明见上游 README，本文件只记录本分支相对上游的改动。

## 本分支改动

- **精简体积**：自绘 `playing_bars_icon.dart` 替换 Rive 图标（移除 `rive_animated_icons`）；移除 `screen_corner_radius`（歌词下拉改用常量 `dragCornerRadius = 12`）及 `flex_color_picker`、`google_fonts` 等无用依赖；应用图标 1.7MB → 0.48MB。
- **竖屏导航重构**：移除侧边抽屉，改用 `root_tab_bar.dart` 底部标签栏（排行 / 最近 / 歌曲 / 歌单 / 艺术家 / 专辑 / 文件夹），支持长按/拖拽排序并持久化到 `setting.json`；新增公共 `MyAppBar` / `MyAppBar.detail()`；设置页改为可返回路由而非切换 root layer。
- **体验修复**：修复横屏超出像素、播放页点击封面缩小动画。
- **构建/发布**：Android 启用 `useLegacyPackaging` 压缩（arm64 APK 约 53.6MB → 27MB）；`AudioService` 增加 `MediaBrowserService` intent-filter；新增 GitHub Actions 发布工作流 `release-android.yml`。

## 许可证

见 `LICENSE`。

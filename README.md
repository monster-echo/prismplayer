# 纯血鸿蒙跨端 WebDAV / 网盘播放器（HarmonyOS NEXT + 鸿蒙 PC）

面向 **HarmonyOS 手机 + 平板 + 鸿蒙电脑（2in1）** 的全端原生高清媒体播放器（对标 Infuse）。基于 **ArkTS + C++ NDK** 架构，主打 **WebDAV / SMB / 网盘（Alist/OpenList + 生态盘）直连流播、全格式硬解/软解兜底、高颜值海报墙刮削、外挂/内封特效字幕渲染、跨端接续与 PC 键鼠深度适配**。

- **目标终端**：`phone` / `tablet` / `2in1`（鸿蒙电脑）
- **商业定位**：买断制 Pro（早鸟 ¥38 / 标准 ¥48 / 家庭跨端 ¥68，支持华为 IAP 非消耗型内购，不搞强制高价年费订阅）
- **开发周期**：6–8 周 MVP 上架（Week 1–4 内核与媒体源，Week 5–6 跨端 UI 与海报墙，Week 7–8 鸿蒙 PC 适配、性能压测与合规提审）

## 目录结构

```text
harmony-webdav-player/
├── README.md               # 项目定位、目录约定与启动清单
└── docs/
    ├── prd.md              # 产品需求文档 v0.1（竞品对标、三端交互、功能边界、商业化与 8 周排期）
    └── architecture.md     # C++ NDK + ArkTS 技术架构设计（播放管线、Range 缓存、字幕渲染与 PC 适配）
```

## 核心技术栈

1. **ArkTS UI 与跨端适配**：Stage 模型、响应式断点（`sm`/`md`/`lg`/`xl`）、`Navigation` 分栏、`2in1` 多窗口与键鼠快捷键、`AVSession` 播控中心、分布式跨端接续。
2. **C++ NDK 播放内核**：
   - **主路径（低功耗硬解）**：`OH_AVDemuxer` / FFmpeg `libavformat` 解封装 + `OH_AVCodec`（`OH_VideoDecoder` / `OH_AudioDecoder`）硬件解码 + `NativeWindow`（`XComponent` 零拷贝送显）+ `OHAudio`（`OH_AudioRenderer`）。
   - **兜底路径（全格式软解）**：FFmpeg（`libavcodec` / `libswresample`）接管冷门编码、多声道混音（DTS/AC3/TrueHD → PCM）与高码率软解。
   - **字幕管线**：`libass` 矢量渲染（ASS/SSA 特效字幕）叠加纹理层 + SRT/VTT/PGS 渲染与字体回退。
3. **流媒体传输层**：`libcurl`（HTTP/2 + 连接池）实现 WebDAV `PROPFIND` 与 HTTP `Range` 分片预读环形缓冲区（RingBuffer），`libsmb2` 支撑局域网 SMB v2/v3 直连。
4. **本地媒体库**：`RelationalStore`（SQLite）存储片源、影片元数据、分集关系与播放进度；本地磁盘缓存海报封面与 NFO 解析结果。

## 本机工具链核验

当前工作区所在环境已安装 DevEco Studio SDK（OpenHarmony API 26，`hvigorw 6.26.8`），具备以下原生多媒体 NDK 头文件：

- `multimedia/player_framework/`：`avplayer.h`、`avmedia_source.h`、`native_avcodec_videodecoder.h`、`native_avdemuxer.h`、`native_avbuffer.h`、`lowpower_video_sink.h`
- `ace/xcomponent/`：`native_interface_xcomponent.h`
- `native_window/`：`external_window.h`
- `ohaudio/`：`native_audiorenderer.h`、`native_audiostreambuilder.h`

## 启动前置清单（Week 0）

- [ ] 在 DevEco Studio 中以 **Native C++** 模板在本目录初始化工程，勾选设备类型 `phone`、`tablet`、`2in1`；
- [ ] 确定最终 `bundleName` 并立即启动 **ICP 备案**（因联网访问 WebDAV/TMDB 需申请 `ohos.permission.INTERNET`，AppGallery 上架强校验）；
- [ ] 同步发邮件开通 **华为 IAP 联运服务**（非消耗型商品：Pro 买断 / 家庭版）与申请 **TMDB API Key**；
- [ ] 准备三端真机调试矩阵：纯血鸿蒙手机、华为平板、鸿蒙 PC（或 2in1 模拟器/真机），以及局域网测试介质（4K HEVC 10bit MKV、Dolby/DTS 音轨、特效 ASS 字幕、WebDAV/Alist 测试源）。

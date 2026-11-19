# 技术架构设计文档（C++ NDK + ArkTS）

本文档定义「纯血鸿蒙 + 鸿蒙 PC 跨端 WebDAV / 网盘播放器」的底层技术架构，重点解决 **流媒体分片预读、硬解零拷贝送显、特效字幕合成、以及 Phone/Tablet/2in1 三端自适应**。

---

## 1. 总体分层架构

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                        ArkTS UI & 应用服务层（Stage 模型）                 │
│  • 响应式布局（Breakpoint: sm/md/lg/xl，2in1 侧边栏/多窗口/快捷键）         │
│  • 媒体库 & 海报墙（RelationalStore、TMDB 刮削调度、NFO 解析）               │
│  • 鉴权与系统集成（HUKS 凭据加密、IAP 买断、AVSession、分布式流转）           │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ NAPI（Async / ThreadSafeFunction / XComponent）
┌───────────────────────────────▼─────────────────────────────────────────┐
│                      C++ NDK 播放与传输引擎（libplayer.so）               │
│                                                                         │
│  ┌─────────────────────┐   ┌──────────────────────────────────────────┐ │
│  │  传输与虚拟文件系统    │   │               播放与同步管线               │ │
│  │  • WebDAV (libcurl) │──▶│  • AVIOContext 自定义回调 (Range Reader)  │ │
│  │  • SMB v2 (libsmb2) │   │  • 解封装：libavformat / OH_AVDemuxer     │ │
│  │  • Local FD / URI   │   │  • 视频解码：OH_VideoDecoder（主） / FFmpeg │ │
│  │  • 环形预读缓存       │   │  • 音频解码：FFmpeg / OH_AudioDecoder     │ │
│  │  • 302 直链缓存      │   │  • 音画同步：Audio Clock 主时钟            │ │
│  └─────────────────────┘   └───────────────┬──────────────────┬─────────┘ │
│                                            │                  │           │
│                            ┌───────────────▼───────┐  ┌───────▼────────┐ │
│                            │  视频 & 字幕合成层      │  │  音频输出层     │ │
│                            │  • NativeWindow       │  │  • OHAudio     │ │
│                            │  • OpenGL ES / EGL    │  │  • AudioRender │ │
│                            │  • libass 字幕纹理叠加  │  │  • 变速不变调   │ │
│                            └───────────────────────┘  └────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 为什么自研 C++ 内核而非仅靠系统 `AVPlayer`

系统 ArkTS `media.AVPlayer` 虽然接入成本低，但在 Infuse 类产品上存在三个致命短板：
1. **协议与认证受限**：对复杂 WebDAV 鉴权（Digest/自签名证书/自定义 Header）、Alist 302 缓存、SMB v2/v3 无法做细粒度并发与预读控制；
2. **字幕与封装受限**：不支持 MKV 内封 ASS/SSA 特效字幕矢量渲染（`libass`），不支持外挂字幕动态延时微调与复杂多音轨（如 DTS-HD/TrueHD 软解混音）；
3. **跨格式兼容性**：对非标准封装（RMVB/FLV/TS/老旧 AVI）以及高码率拖动 Seek 的缓冲状态机可控性差。

因此采用 **「自研 C++ 管线 + 系统硬解能力复用」** 路线：
- 解封装与网络流控由可控的 `FFmpeg (libavformat)` + `libcurl/libsmb2` 负责；
- 视频硬件解码直接调用 HarmonyOS NDK 的 **`OH_VideoDecoder`**（`multimedia/player_framework/native_avcodec_videodecoder.h`），兼顾 4K HEVC/AV1 低功耗与流畅度；软解自动回退至 FFmpeg。

---

## 3. 核心模块设计

### 3.1 流媒体 I/O 与 Range 环形缓存（`DataSource`）

针对 WebDAV / Alist 网盘场景，高码率 MKV 在播放中会频繁触发头尾索引读取（Moov / Cues）以及用户拖拽 Seek：

1. **自定义 `AVIOContext`**：将 FFmpeg 的 `read_packet` / `seek` 接管到 C++ `BufferedStream`。
2. **双层缓存策略**：
   - **环形预读缓冲（RingBuffer）**：默认 64MB（可在设置中选择 32MB/64MB/128MB），后台读线程以分片（如 2MB/chunk）流水线拉取 `Range: bytes=start-end`。
   - **尾/头元数据小缓存（Metadata Cache）**：MKV/MP4 启动或 Seek 时常在文件头部与尾部小范围来回跳读；命中缓存窗口内的数据直接内存返回，避免反复新建 HTTP 请求导致网盘 QPS 触发限流。
3. **302 重定向直链缓存（Alist 专项）**：
   - 首次请求 WebDAV URL 若返回 `302/307`，记录最终直链与过期时间（默认 TTL 10 分钟或依据直链签名参数判断），后续分片 `Range` 直接请求直链，大幅降低 Alist 网关压力与卡顿。
   - 若直链返回 `401/403`，自动失效缓存并回源原始 WebDAV URL 重新获取。
4. **并发连接池**：`libcurl` 启用 HTTP/2 多路复用与 TLS Session 复用；支持用户切换「严格校验证书 / 信任局域网自签名证书」。

### 3.2 视频解码与零拷贝送显（`OH_VideoDecoder` + `XComponent`）

```text
FFmpeg AVPacket (Annex-B / AVCC)
   │  (必要时经过 h264_mp4toannexb / hevc_mp4toannexb BSF)
   ▼
OH_VideoDecoder (Surface Mode / Buffer Mode)
   │  native_avcodec_videodecoder.h + native_avbuffer.h
   ├──▶ [无特效字幕快速路径] 直接绑定 XComponent NativeWindow (零拷贝硬解上屏)
   └──▶ [有 ASS/图形字幕或画面调色] 解码输出至 SurfaceTexture/ImageReader
                                   ──▶ EGL / OpenGL ES 与 libass RGBA 纹理合成上屏
```

- **Surface 模式优先**：在无特效字幕且未开启色彩调节时，`OH_VideoDecoder_SetSurface` 直接绑定 `XComponent` 提供的 `OHNativeWindow`（`ace/xcomponent/native_interface_xcomponent.h` + `native_window/external_window.h`），实现真正的零拷贝高帧率 4K60 播放，显著降低手机发热。
- **GL 合成路径（字幕/调色开启时）**：
  - 将硬解输出的 `OHNativeWindow` / `OH_NativeImage` 作为外部纹理（`GL_TEXTURE_EXTERNAL_OES`），在 OpenGL ES 3.0 Shader 中完成视频帧采样 + 亮度/对比度/饱和度矩阵调节；
  - `libass` 仅在字幕内容变化（`ass_render_frame` 返回 `changed != 0`）时更新脏矩形 RGBA 纹理，通过 Alpha Blending 叠加到视频帧上，再 SwapBuffers 到 `XComponent` 的 `OHNativeWindow`。
- **软解兜底**：当 `OH_AVCapability` 查询不支持该编码/Profile，或硬解运行期报错（如特殊 10bit 4:2:2 Profile），无缝切换至 FFmpeg `libavcodec` 软解输出 YUV420P/NV12 至 GL Shader 渲染。

### 3.3 音频管线与同步（`OHAudio` + `libswresample`）

- **音频解码**：统一通过 FFmpeg 软解（AAC/FLAC/OPUS/AC3/EAC3/DTS/TrueHD）或 `OH_AudioDecoder`，再经 `libswresample` 统一重采样为 `48kHz / Float32`（多声道按设备能力 Downmix 为 Stereo 2.0 或透传多声道）。
- **变速不变调**：集成 `SoundTouch`（或 FFmpeg `atempo` 滤镜）实现 0.5x–4.0x 倍速播放不改变音高。
- **音频输出**：使用 `ohaudio/native_audiostreambuilder.h` 与 `ohaudio/native_audiorenderer.h` 创建低延迟音频渲染器（`AUDIOSTREAM_USAGE_MOVIE`），在回调函数中从音频 PCM 队列拉取数据，并实时更新 **Audio Clock**。
- **音画同步**：以 **Audio Clock 为主时钟**；视频渲染线程根据当前帧 PTS 与 Audio Clock 的差值计算休眠或丢帧（diff > +40ms 丢非关键帧或加速追帧，diff < -15ms 等待垂直同步），保证长时间播放零漂移。

### 3.4 线程模型

| 线程 | 职责 | 生命周期 |
|---|---|---|
| **ArkTS 主线程（UI）** | 页面渲染、手势/键盘事件、进度条节流刷新（250ms） | 应用全局 |
| **Network Reader 线程** | `libcurl` / `libsmb2` 分片拉取写入 RingBuffer，支持 Seek 中断唤醒 | 单次播放实例 |
| **Demux 线程** | 读取 `AVPacket`，分别压入 VideoPacketQueue 与 AudioPacketQueue（有界阻塞队列） | 单次播放实例 |
| **Video Decode & Render 线程** | 驱动 `OH_VideoDecoder` 输入/输出、音画同步与 EGL/NativeWindow 提交 | 单次播放实例 |
| **Audio Decode 线程** | 解码音频并做重采样/SoundTouch，填充 PCM RingBuffer 供 OHAudio 回调消费 | 单次播放实例 |
| **Scraper Worker（ArkTS TaskPool）** | 媒体源目录扫描、文件名正则解析、NFO 读取与 TMDB API 并发限速请求 | 按需后台任务 |

---

## 4. 鸿蒙三端自适应与 PC（2in1）专项架构

### 4.1 响应式断点体系
在 `EntryAbility` 监听 `windowStage.getMainWindowSync().on('windowSizeChange')`，结合 `display` 密度计算窗口断点：
- `sm`（< 600vp）：手机竖屏单列海报墙，底部 Navigation Tab，播放页全屏沉浸手势。
- `md`（600vp–840vp）：折叠屏展开/小平板，双栏布局（左侧精简导航 + 右侧媒体网格）。
- `lg` / `xl`（>= 840vp，含 **鸿蒙 PC 2in1**）：桌面级三区域结构（常驻可折叠侧边栏 + 顶部工具栏/搜索 + 自适应列数海报墙）。

### 4.2 鸿蒙 PC（2in1）原生能力接入
1. **多窗口与窗口控制**：支持自由拖拽窗口缩放，播放页支持「置顶窗口」「隐藏标题栏影院模式」「独立子窗口播放」以及画中画（PiP）。
2. **全局键鼠事件**：在播放页根容器绑定 `onKeyEvent` 与 `onMouse` / `PanGesture`：
   - 鼠标移动唤醒底部 OSD 控制条，静止 3 秒后自动隐藏光标与控制条；
   - 滚轮上下映射为音量调节，双击画面切换全屏/还原；
   - 键盘快捷键映射表可配置（默认对齐 IINA/PotPlayer 习惯）。
3. **文件拖拽与系统文件关联**：
   - 播放页与首页支持 `onDrop` 接收本地文件 URI（视频直接起播，`.ass/.srt` 拖入直接挂载为当前外挂字幕）；
   - `module.json5` 的 `abilities[0].skills` 声明支持常见视频 MIME/后缀（`.mkv` `.mp4` `.mov` `.ts` `.avi` `.flv`），支持在鸿蒙 PC 文件管理器中右键「打开方式」直接唤起播放。

---

## 5. 数据存储与安全设计

### 5.1 本地数据库（`RelationalStore`）
核心表结构规划：
- `media_source`：`id`, `name`, `type` (`local`|`webdav`|`smb`), `base_url`, `username`, `credential_key` (指向 HUKS), `extra_json` (忽略证书/302策略)
- `media_item`：`id`, `source_id`, `path`, `file_name`, `file_size`, `media_type` (`movie`|`episode`|`other`), `tmdb_id`, `series_id`, `season_no`, `episode_no`, `title`, `overview`, `poster_local_path`, `backdrop_local_path`, `rating`, `year`
- `watch_history`：`item_id`, `position_ms`, `duration_ms`, `audio_track_idx`, `subtitle_track_idx`, `subtitle_delay_ms`, `playback_rate`, `updated_at`, `is_finished`

### 5.2 凭据安全（`HUKS`）
- 所有 WebDAV / SMB 密码与 Token **严禁明文落库**；
- 通过 `@ohos.security.huks` 生成设备绑定 AES-GCM 密钥加密凭据密文，仅在 C++ 传输层发起连接前于内存中短暂解密使用。

---

## 6. 第三方 C/C++ 依赖与交叉编译清单

全部通过 HarmonyOS NDK (`aarch64-linux-ohos` 与 `x86_64-linux-ohos` 模拟器调试按需) 静态或规范动态编译至 `entry/libs/arm64-v8a/`：

| 库名 | 版本建议 | 协议 | 用途 |
|---|---|---|---|
| **FFmpeg** | 6.1 / 7.0（LGPL 配置） | LGPL v2.1+ | 解封装、BSF、软解兜底、`libswresample` |
| **libcurl** + **OpenSSL / MbedTLS** | 8.x + OpenSSL 3.x | MIT / Apache-2.0 | WebDAV HTTP/2、HTTPS 双向/自签名控制、Range 并发 |
| **libsmb2** | 5.x / 6.x | LGPL v2.1 | 局域网 SMB v2/v3 浏览与流式读取 |
| **libass** + **freetype** + **harfbuzz** + **fribidi** | 最新稳定版 | ISC / FTL / MIT | ASS/SSA 特效字幕光栅化与复杂文字排版 |
| **pugixml** / **tinyxml2** | 最新稳定版 | MIT / Zlib | WebDAV `PROPFIND` XML 响应解析与 `.nfo` 解析 |
| **SoundTouch** | 2.3.x | LGPL v2.1 | 倍速播放音频不变调处理 |

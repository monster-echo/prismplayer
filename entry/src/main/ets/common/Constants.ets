import { HardwareCodecRule } from './Types';

export type BreakpointType = 'sm' | 'md' | 'lg' | 'xl';

export class AppConstants {
  static readonly BUNDLE_NAME: string = 'tech.zhongbei.prismplayer';
  static readonly DB_NAME: string = 'prism_player.db';
  static readonly PREFS_NAME: string = 'prism_prefs';
  static readonly DEFAULT_TMDB_HOST: string = 'https://api.themoviedb.org/3';
  static readonly DEFAULT_TMDB_IMAGE_BASE: string = 'https://image.tmdb.org/t/p/w500';
  static readonly DEFAULT_CACHE_MB: number = 64;
  static readonly FREE_MAX_SOURCES: number = 1;
  static readonly FREE_MAX_LIBRARY_ITEMS: number = 999999;

  static readonly VIDEO_EXTENSIONS: string[] = [
    '.mp4', '.mkv', '.mov', '.ts', '.m2ts', '.avi', '.flv', '.webm', '.m4v', '.rmvb', '.mpg', '.mpeg'
  ];
  static readonly SUBTITLE_EXTENSIONS: string[] = [
    '.ass', '.ssa', '.srt', '.vtt'
  ];
  /** 音乐曲目：系统 AVPlayer 原生支持的无损 / 有损格式，SMB 与网盘目录同样适用。 */
  static readonly AUDIO_EXTENSIONS: string[] = [
    '.mp3', '.flac', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.ape', '.wma', '.aiff', '.aif', '.alac', '.dsf'
  ];
  static readonly IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp'];
  /** 本机存储片源的固定 ID：历史版本导入的条目都挂着这个 sourceId，不能改。 */
  static readonly LOCAL_SOURCE_ID: string = 'local_device';
  static readonly LOCAL_SOURCE_NAME: string = '本机存储';
  static readonly PLAYBACK_RATES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  /**
   * 可交给系统播放器（OH_AVPlayer）硬解的封装白名单。
   *
   * 依据 Media Kit 官方支持表：mp4 / mkv / ts 均支持 H.264、H.265(10+) 视频与 AAC/MP3 音频。
   * MKV 不再一刀切软解——只有命中 DTS/TrueHD/AC3 等系统不支持的音轨时才降级（见 Formatters）。
   */
  static readonly DEFAULT_HARDWARE_SUPPORTED_FORMATS: string[] = [
    'mp4', 'm4v', 'mov', 'm3u8', 'ts', 'mkv', 'webm', 'h264', 'hevc', 'aac', 'flac', 'mp3'
  ];

  static readonly HARDWARE_CODEC_MATRIX: HardwareCodecRule[] = [
    { format: 'mp4', label: 'MP4 / M4V', category: 'container', desc: '标准 MP4 流媒体与抖音/网页直链封装', defaultHw: true },
    { format: 'mov', label: 'MOV (QuickTime)', category: 'container', desc: 'Apple QuickTime / iPhone 拍摄原片封装', defaultHw: true },
    { format: 'm3u8', label: 'HLS (.m3u8 / .ts)', category: 'container', desc: 'HTTP Live Streaming 切片与直播传输流', defaultHw: true },
    { format: 'webm', label: 'WebM', category: 'container', desc: 'Web 开放媒体容器封装', defaultHw: true },
    { format: 'mkv', label: 'MKV (Matroska)', category: 'container', desc: '多音轨蓝光封装：H.264/H.265 可硬解，命中 DTS/TrueHD 音轨时自动降级软解', defaultHw: true },
    { format: 'avi', label: 'AVI (XviD / DivX)', category: 'container', desc: '传统 AVI 交错封装（系统硬解不支持，直接走 FFmpeg 软解）', defaultHw: false },
    { format: 'rmvb', label: 'RMVB / FLV / MPG', category: 'container', desc: 'RealMedia / Flash / MPEG-PS 怀旧封装（直接走 FFmpeg 软解）', defaultHw: false },
    { format: 'h264', label: 'H.264 / AVC', category: 'video', desc: '8-bit 硬件加速解码（最高 4K 60fps）', defaultHw: true },
    { format: 'hevc', label: 'H.265 / HEVC', category: 'video', desc: 'Main / Main10 HDR10 硬件加速解码', defaultHw: true },
    { format: 'av1', label: 'AV1 / VP9', category: 'video', desc: '新一代高压缩编码（部分芯片需 FFmpeg 软解）', defaultHw: false },
    { format: 'aac', label: 'AAC / FLAC / MP3', category: 'audio', desc: '标准立体声与无损音频直通硬解', defaultHw: true },
    { format: 'dts', label: 'DTS-HD / TrueHD / EAC3', category: 'audio', desc: '多声道源码音轨（系统硬解易无声或报错，自动路由 FFmpeg 软解）', defaultHw: false }
  ];

  /**
   * App Linking 落地域名。必须在 AGC「App Linking」里把该域名配置为本应用所有，
   * 并在 values/string 的 ohos_mutual_auth / module.json5 的 uris 中同步声明；
   * 未配置前分享出去的链接只会落商店，不会直达播放。
   */
  static readonly APP_LINK_BASE: string = 'https://prismplayer.zhongbei.tech/link';

  // IAP Product IDs (replace with AppGallery Connect configured IDs before release)
  static readonly IAP_PRO_STANDARD: string = 'prism_pro_lifetime';
  static readonly IAP_PRO_FAMILY: string = 'prism_pro_family';

  // 内置字幕源（SubDL）访问凭据，应用内不展示
  static readonly SUBDL_API_KEY: string = 'subdl_ZqYY18HnlHcvH1y7fnslrxVOFMtFNHECdkXOrm0pGh0';

  // 内置字幕源（OpenSubtitles）访问凭据，应用内不展示；账号开通 API 权限前该源自动跳过
  static readonly OPENSUBTITLES_API_KEY: string = '5ed03aee65c5d26e0a0152a10dca2bb3';
  static readonly OPENSUBTITLES_USER_TOKEN: string = 'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI1ZWQwM2FlZTY1YzVkMjZlMGEwMTUyYTEwZGNhMmJiMyIsIm5iZiI6MTc5NTA5NDYxOS4yMTEsInN1YiI6IjZhZmVmODViZjU4YzAyNmY5MTdmZTZkNCIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.lbgEHnBuPZb01Ze16RTvFGjnTJ6JY0ROaN-k-0ErZVI';

  /** 合规联系邮箱（AGC / 隐私政策 / 用户协议统一使用） */
  static readonly SUPPORT_EMAIL: string = 'hello@zhongbei.tech';
  /**
   * 用户群：走 feishu:// 私有 scheme，只有装了飞书才会被接住，
   * 否则 startAbility 抛错，UI 回落到二维码（用 https applink 会被浏览器吃掉，无法判断）。
   */
  static readonly FEISHU_GROUP_URL: string = 'feishu://client/chat/chatter/add_by_link?link_token=eecvd18d-58af-457a-9a29-bbaa46c46a5e&qr_code=true';
  static readonly POLICY_UPDATED_DATE: string = '2026年11月19日';
}

export interface ShortcutTip {
  keys: string;
  action: string;
}

export const PC_SHORTCUTS: ShortcutTip[] = [
  { keys: 'Space', action: '播放 / 暂停' },
  { keys: '← / →', action: '快退 / 快进 5 秒' },
  { keys: 'Shift + ← / →', action: '快退 / 快进 30 秒' },
  { keys: '↑ / ↓', action: '音量 +5% / -5%' },
  { keys: 'F / 双击画面', action: '切换全屏' },
  { keys: 'Esc', action: '退出全屏或关闭浮层' },
  { keys: '[ / ]', action: '降低 / 提高播放倍速' },
  { keys: 'S', action: '打开字幕中心' },
  { keys: 'A', action: '打开音轨切换面板' },
  { keys: 'I', action: '显示 / 隐藏技术统计 OSD' },
  { keys: 'M', action: '静音 / 取消静音' }
];

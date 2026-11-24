export type MediaSourceType = 'webdav' | 'alist' | 'smb' | 'plex' | 'emby' | 's3' | 'youtube' | 'douyin' | 'bilibili' | 'iptv' | 'local';

export interface SourceExtraConfig {
  region?: string;
  usePathStyle?: boolean;
  mirrorUrl?: string;
  qualityPref?: string;
  userAgent?: string;
  referer?: string;
  cookie?: string;
}

export function parseSourceExtra(raw?: string): SourceExtraConfig {
  if (!raw) return {};
  try {
    const obj = JSON.parse(raw) as SourceExtraConfig;
    return obj && typeof obj === 'object' ? obj : {};
  } catch (_e) {
    return {};
  }
}

export function serializeSourceExtra(cfg: SourceExtraConfig): string {
  try {
    return JSON.stringify(cfg);
  } catch (_e) {
    return '{}';
  }
}

export type MediaCategory = 'all' | 'movie' | 'tv' | 'music' | 'favorite' | 'private';

/** 条目种类：电影 / 剧集单集 / 音乐曲目。音乐走独立播放器，不进入视频链路。 */
export type MediaKind = 'movie' | 'episode' | 'track';

export interface SubtitleTrackOption {
  label: string;
  lang: string;
  url: string;
  format?: string;
}

export type DecoderEngineMode = 'native_hw' | 'ffmpeg_sw';

export type AspectMode = 'fit' | 'fill' | '16:9' | '21:9' | '4:3';

export type ProTier = 'free' | 'pro_early' | 'pro_lifetime' | 'pro_family';

export interface MediaSource {
  id: string;
  name: string;
  type: MediaSourceType;
  baseUrl: string;
  rootPath: string;
  username: string;
  password: string; // Stored encrypted via HUKS when persisted
  allowInsecureTls: boolean;
  cacheAlist302: boolean;
  createdAt: number;
  lastScannedAt: number;
  extraConfig?: string;
}

export interface RemoteFileEntry {
  name: string;
  path: string;
  fullUrl: string;
  isDirectory: boolean;
  size: number;
  lastModified: string;
  contentType: string;
  isVideo: boolean;
  isSubtitle: boolean;
  /** 音频文件；本机片源与远端目录都可能命中，缺省视为非音频 */
  isAudio?: boolean;
  /** 图片文件（封面 / 海报），本机片源用于取专辑封面 */
  isImage?: boolean;
}

export interface MediaItem {
  id: string;
  sourceId: string;
  sourceType: MediaSourceType;
  remotePath: string;
  streamUrl: string;
  fileName: string;
  fileSize: number;
  mediaType: MediaKind;
  seriesKey: string;
  seriesTitle: string;
  seasonNo: number;
  episodeNo: number;
  title: string;
  originalTitle: string;
  year: number;
  overview: string;
  posterUrl: string;
  backdropUrl: string;
  rating: number;
  qualityTag: string;
  tmdbId: number;
  durationMs: number;
  subtitleUrl: string;
  subtitleTracks?: SubtitleTrackOption[];
  isFavorite?: boolean;
  addedAt: number;
  /** 音乐曲目：歌手 / 专辑 / 曲序（媒体标签优先，缺失时按目录与文件名推断） */
  artist?: string;
  album?: string;
  trackNo?: number;
}

/** 音乐专辑：按「同一片源 + 专辑名 + 歌手」聚合，封面取曲目关联的目录封面。 */
export interface MusicAlbum {
  albumKey: string;
  album: string;
  artist: string;
  coverUrl: string;
  tracks: MediaItem[];
}

/** 音乐播放页入参：从某首开始，携带整张专辑 / 整个目录的队列。 */
export interface MusicLaunchParams {
  item: MediaItem;
  queue: MediaItem[];
}

export interface SeriesGroup {
  seriesKey: string;
  title: string;
  posterUrl: string;
  backdropUrl: string;
  overview: string;
  year: number;
  rating: number;
  tmdbId: number;
  episodes: MediaItem[];
}

export interface WatchHistoryRecord {
  itemId: string;
  title: string;
  subtitleLabel: string;
  posterUrl: string;
  streamUrl: string;
  sourceId: string;
  positionMs: number;
  durationMs: number;
  audioTrackIndex: number;
  subtitleTrackIndex: number;
  subtitleDelayMs: number;
  playbackRate: number;
  // Burned-in subtitle mask: maskEnabled uses -1 = never configured (fall back to global default), 0 = off, 1 = on;
  // mask band is normalized (0..1) against the video picture area so letterbox changes never invalidate it
  maskEnabled: number;
  maskYTop: number;
  maskYBottom: number;
  updatedAt: number;
  finished: boolean;
}

export interface ParsedFilenameInfo {
  cleanTitle: string;
  year: number;
  mediaType: 'movie' | 'episode';
  seasonNo: number;
  episodeNo: number;
  qualityTag: string;
}

/** 音频文件解析结果：目录推断 + 文件名兜底，媒体标签命中时由调用方覆盖。 */
export interface ParsedTrackInfo {
  title: string;
  artist: string;
  album: string;
  trackNo: number;
}

export interface SubtitleCue {
  index: number;
  startMs: number;
  endMs: number;
  text: string;
  alignment: number; // 1..9 ASS numpad alignment (default 2 = bottom center)
  colorHex: string;
  isBold: boolean;
  isItalic: boolean;
  layer: number;
}

export type SubtitleLangTag = 'zh' | 'en' | 'zh-en' | 'und';

export interface ExternalSubtitleTrack {
  id: string;
  label: string;
  format: 'ass' | 'ssa' | 'srt' | 'vtt';
  sourceUrl: string;
  langTag: SubtitleLangTag;
  cues: SubtitleCue[];
}

export interface PlayerTrackItem {
  index: number;
  kind: 'audio' | 'video' | 'subtitle';
  label: string;
  language: string;
  codec: string;
  details: string;
}

export interface PlayerLaunchParams {
  item: MediaItem;
  source?: MediaSource;
  startPositionMs?: number;
  playlist?: MediaItem[];
  audioTrackIndex?: number;
  subtitleTrackIndex?: number;
  subtitleDelayMs?: number;
  playbackRate?: number;
}

/** 外部来源请求的一次页面跳转。 */
export interface RouteRequest {
  url: string;
  params: Object;
}

export interface OnlineMediaParams {
  /** 从首页「剪贴板链接」快捷入口带过来的链接，进页面即预填。 */
  clipboardUrl?: string;
}

export interface LegalDocParams {
  docType: 'privacy' | 'agreement';
}

export interface MediaDetailParams {
  movie?: MediaItem;
  series?: SeriesGroup;
}

export interface SourceFormParams {
  editingSource?: MediaSource;
}

export interface SourceBrowserParams {
  source: MediaSource;
  initialPath?: string;
}

export type VaultEntryKind = 'series' | 'movie' | 'folder';

export interface VaultEntry {
  id: string;
  sourceId: string;
  kind: VaultEntryKind;
  targetKey: string;
  title: string;
  posterUrl: string;
  createdAt: number;
}

export interface HiddenFolderRule {
  id: string;
  sourceId: string;
  folderPath: string;
  folderName: string;
  createdAt: number;
}

export interface HardwareCodecRule {
  format: string;
  label: string;
  category: 'container' | 'video' | 'audio';
  desc: string;
  defaultHw: boolean;
}

export interface DecodeRoutingDecision {
  engine: 'native_hw' | 'ffmpeg_sw';
  matchedFormat: string;
  reason: string;
}

export type SubtitleLanguageMode = 'all' | 'zh' | 'en';

/** In-player subtitle screen routes: one screen per subtitle responsibility. */
export type SubtitlePageRoute = 'none' | 'hub' | 'tracks' | 'style' | 'sync' | 'online' | 'assist' | 'mask';

/** Persisted subtitle appearance defaults, shared by the player style screen and the settings page. */
export interface SubtitleStyleValues {
  fontSizeFp: number;
  bgEnabled: boolean;
  bgOpacityPercent: number;
  verticalOffsetVp: number;
  languageMode: SubtitleLanguageMode;
}

export interface SubtitleSearchLanguage {
  code: string;
  label: string;
}

export const SUBTITLE_SEARCH_LANGUAGES: SubtitleSearchLanguage[] = [
  { code: 'all', label: '全部语言' },
  { code: 'zh', label: '中文' },
  { code: 'en', label: '英文' },
  { code: 'ja', label: '日文' },
  { code: 'ko', label: '韩文' },
  { code: 'fr', label: '法文' },
  { code: 'de', label: '德文' },
  { code: 'es', label: '西班牙语' }
];

export type ThemeMode = 'system' | 'light' | 'dark';

export interface AppSettings {
  themeMode: ThemeMode;
  cacheBudgetMb: number;
  preferHardwareDecode: boolean;
  hardwareSupportedFormats?: string[];
  tmdbApiKey: string;
  tmdbApiHost: string;
  tmdbImageBase: string;
  autoSkipIntroSec: number;
  autoSkipOutroSec: number;
  subtitleFontSizeFp: number;
  subtitleLanguageMode: SubtitleLanguageMode;
  subtitleBgEnabled: boolean;
  subtitleBgOpacityPercent: number;
  subtitleVerticalOffsetVp: number;
  burnSubMaskDefault: boolean;
  subdlApiKey: string;
  proTier: ProTier;
  privacyAccepted: boolean;
  vaultPinCipher?: string;
}

export interface LibraryTabSummary {
  totalMovies: number;
  totalSeries: number;
  totalEpisodes: number;
}

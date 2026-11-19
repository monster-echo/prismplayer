import { AppConstants } from './Constants';
import { DecodeRoutingDecision, MediaItem, ParsedFilenameInfo, RemoteFileEntry, SubtitleTrackOption } from './Types';

export class Formatters {
  static formatDuration(ms: number): string {
    if (!ms || ms < 0 || !isFinite(ms)) {
      return '00:00';
    }
    const totalSec = Math.floor(ms / 1000);
    const hours = Math.floor(totalSec / 3600);
    const mins = Math.floor((totalSec % 3600) / 60);
    const secs = totalSec % 60;
    const mm = mins < 10 ? `0${mins}` : `${mins}`;
    const ss = secs < 10 ? `0${secs}` : `${secs}`;
    if (hours > 0) {
      const hh = hours < 10 ? `0${hours}` : `${hours}`;
      return `${hh}:${mm}:${ss}`;
    }
    return `${mm}:${ss}`;
  }

  static formatBytes(bytes: number): string {
    if (!bytes || bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = bytes;
    let idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value /= 1024;
      idx++;
    }
    return idx === 0 ? `${Math.round(value)} B` : `${value.toFixed(idx >= 3 ? 2 : 1)} ${units[idx]}`;
  }

  static formatRelativeTime(timestampMs: number): string {
    if (!timestampMs) return '';
    const diff = Date.now() - timestampMs;
    if (diff < 60000) return '刚刚';
    if (diff < 3600000) return `${Math.floor(diff / 60000)} 分钟前`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)} 小时前`;
    const days = Math.floor(diff / 86400000);
    if (days < 30) return `${days} 天前`;
    const d = new Date(timestampMs);
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  }

  static hasExtension(fileName: string, exts: string[]): boolean {
    const lower = fileName.toLowerCase();
    for (let i = 0; i < exts.length; i++) {
      if (lower.endsWith(exts[i])) {
        return true;
      }
    }
    return false;
  }

  static isVideoFile(fileName: string): boolean {
    return Formatters.hasExtension(fileName, AppConstants.VIDEO_EXTENSIONS);
  }


  /**
   * 同目录 sidecar 字幕匹配：视频基底名完全相等，或字幕基底名以「视频名. / _ / 空格」开头；
   * 另做去空格宽松对比（「第 1 集」vs「第1集」）。返回一个或多个关联字幕轨道。
   */
  static matchSidecarSubtitles(entries: RemoteFileEntry[], videoName: string): SubtitleTrackOption[] {
    const baseLower = Formatters.stripExtension(videoName).toLowerCase();
    const normBase = baseLower.replace(/\s+/g, '');
    const matched: SubtitleTrackOption[] = [];
    for (let sIdx = 0; sIdx < entries.length; sIdx++) {
      const se = entries[sIdx];
      if (!se.isSubtitle) continue;
      const subBase = Formatters.stripExtension(se.name).toLowerCase();
      const subNorm = subBase.replace(/\s+/g, '');
      const hit = subBase === baseLower
        || subBase.startsWith(baseLower + '.') || subBase.startsWith(baseLower + '_') || subBase.startsWith(baseLower + ' ')
        || (normBase.length > 0 && (subNorm === normBase || subNorm.startsWith(normBase + '.')));
      if (!hit) continue;
      const detected = Formatters.detectSubtitleLanguage(se.name, matched.length);
      matched.push({
        lang: detected.lang,
        label: detected.label,
        url: se.fullUrl,
        format: se.name.substring(se.name.lastIndexOf('.') + 1).toLowerCase()
      });
    }
    return matched;
  }

  static isSubtitleFile(fileName: string): boolean {
    return Formatters.hasExtension(fileName, AppConstants.SUBTITLE_EXTENSIONS);
  }

  static stripExtension(fileName: string): string {
    const dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  static encodeBase64Utf8(input: string): string {
    const bytes: number[] = [];
    for (let i = 0; i < input.length; i++) {
      const code = input.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code < 0xd800 || code >= 0xe000) {
        bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      } else {
        i++;
        const cp = 0x10000 + (((code & 0x3ff) << 10) | (input.charCodeAt(i) & 0x3ff));
        bytes.push(
          0xf0 | (cp >> 18),
          0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f),
          0x80 | (cp & 0x3f)
        );
      }
    }
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out = '';
    for (let i = 0; i < bytes.length; i += 3) {
      const b0 = bytes[i];
      const hasB1 = i + 1 < bytes.length;
      const hasB2 = i + 2 < bytes.length;
      const b1 = hasB1 ? bytes[i + 1] : 0;
      const b2 = hasB2 ? bytes[i + 2] : 0;
      const triple = (b0 << 16) | (b1 << 8) | b2;
      out += chars.charAt((triple >> 18) & 0x3f);
      out += chars.charAt((triple >> 12) & 0x3f);
      out += hasB1 ? chars.charAt((triple >> 6) & 0x3f) : '=';
      out += hasB2 ? chars.charAt(triple & 0x3f) : '=';
    }
    return out;
  }

  static buildBasicAuthHeader(username: string, password: string): string {
    if (!username && !password) {
      return '';
    }
    return `Basic ${Formatters.encodeBase64Utf8(`${username}:${password}`)}`;
  }

  static parseMediaFilename(fileName: string): ParsedFilenameInfo {
    const base = Formatters.stripExtension(fileName);
    const upper = base.toUpperCase();

    // Detect quality tags
    const tags: string[] = [];
    if (upper.includes('2160P') || upper.includes('4K') || upper.includes('UHD')) {
      tags.push('4K');
    } else if (upper.includes('1080P')) {
      tags.push('1080P');
    } else if (upper.includes('720P')) {
      tags.push('720P');
    }
    if (upper.includes('DV') || upper.includes('DOLBY') || upper.includes('DOVI')) {
      tags.push('Dolby');
    } else if (upper.includes('HDR')) {
      tags.push('HDR');
    }
    if (upper.includes('X265') || upper.includes('H265') || upper.includes('HEVC')) {
      tags.push('HEVC');
    } else if (upper.includes('AV1')) {
      tags.push('AV1');
    }
    const qualityTag = tags.length > 0 ? tags.join(' · ') : 'HD';

    // Detect S01E02 / 1x02 / EP02 / 第02集
    let mediaType: 'movie' | 'episode' = 'movie';
    let seasonNo = 1;
    let episodeNo = 0;
    let cutIndex = base.length;

    const seMatch = base.match(/[._\s\-\[]S(\d{1,2})[._\s]?E(\d{1,3})/i);
    if (seMatch && seMatch.index !== undefined) {
      mediaType = 'episode';
      seasonNo = parseInt(seMatch[1], 10);
      episodeNo = parseInt(seMatch[2], 10);
      cutIndex = Math.min(cutIndex, seMatch.index);
    } else {
      const epMatch = base.match(/[._\s\-\[](?:EP|E)(\d{1,3})(?:[._\s\-\]]|$)/i);
      const cnEpMatch = base.match(/第(\d{1,3})[集话]/);
      if (epMatch && epMatch.index !== undefined) {
        mediaType = 'episode';
        episodeNo = parseInt(epMatch[1], 10);
        cutIndex = Math.min(cutIndex, epMatch.index);
      } else if (cnEpMatch && cnEpMatch.index !== undefined) {
        mediaType = 'episode';
        episodeNo = parseInt(cnEpMatch[1], 10);
        cutIndex = Math.min(cutIndex, cnEpMatch.index);
      }
    }

    // Detect release year (1920..2035)
    let year = 0;
    const yearMatch = base.match(/[\.\s\(\[_]((?:19|20)\d{2})(?:[\.\s\)\]_]|$)/);
    if (yearMatch && yearMatch.index !== undefined) {
      const parsedYear = parseInt(yearMatch[1], 10);
      if (parsedYear >= 1920 && parsedYear <= 2035) {
        year = parsedYear;
        cutIndex = Math.min(cutIndex, yearMatch.index);
      }
    }

    // Also cut at resolution tokens if year was missing
    const resMatch = base.match(/[\.\s\[_](2160p|1080p|720p|4K|BluRay|WEB-DL|WEBRip|REMUX|x264|x265|HEVC)/i);
    if (resMatch && resMatch.index !== undefined) {
      cutIndex = Math.min(cutIndex, resMatch.index);
    }

    let rawTitle = base.substring(0, cutIndex);
    rawTitle = rawTitle.replace(/[\._]+/g, ' ').replace(/\[[^\]]*\]/g, ' ').trim();
    if (!rawTitle) {
      rawTitle = base.replace(/[\._]+/g, ' ').trim();
    }

    return {
      cleanTitle: rawTitle,
      year,
      mediaType,
      seasonNo,
      episodeNo,
      qualityTag
    };
  }

  /** Converts raw network, WebDAV, or decoder error details into warm, actionable user-facing copy. */
  static toFriendlyError(raw: string, isRemotePlayback: boolean = false): string {
    const lower = (raw || '').toLowerCase();
    if (lower.includes('401') || lower.includes('403') || lower.includes('unauth') ||
        lower.includes('signaturedoesnotmatch') || lower.includes('invalidaccesskeyid') || lower.includes('accessdenied') ||
        lower.includes('logon_failure') || lower.includes('无权访问') || lower.includes('token 无效')) {
      return '鉴权未通过验证（账号、Token 或 S3 Key 无效），请前往「片源管理」核对凭据后重试。';
    }
    if (lower.includes('youtube') || lower.includes('signaturecipher') || lower.includes('sign in to confirm') || lower.includes('piped') || lower.includes('invidious')) {
      return raw.length < 120 ? raw : 'YouTube 视频流解析受限，请在片源设置填写 Invidious / Piped 镜像服务地址后重试。';
    }
    if (lower.includes('404') || lower.includes('not found') || lower.includes('no such') || lower.includes('不存在')) {
      return '未在服务器找到该视频或文件夹，可能已被移动或重命名，请刷新列表后再试。';
    }
    if (lower.includes('ssl') || lower.includes('tls') || lower.includes('cert')) {
      return '安全证书校验未通过，建议在片源编辑页开启“信任局域网自签名 HTTPS 证书”。';
    }
    if (lower.includes('timeout') || lower.includes('timed out') || lower.includes('超时')) {
      return '服务器响应时间较长，请检查当前网络状态或稍后重试。';
    }
    if (
      lower.includes('connect') ||
      lower.includes('refused') ||
      lower.includes('unreachable') ||
      lower.includes('network') ||
      lower.includes('无法连接') ||
      (isRemotePlayback && lower.includes('-10000'))
    ) {
      return '暂时未能连上片源服务器，请确认 NAS 或网盘服务已开启，且与当前设备网络互通。';
    }
    if (lower.includes('-10000') || lower.includes('unsupport') || lower.includes('codec') || lower.includes('decode')) {
      return '当前解码方式暂不兼容此视频格式，建议切换解码引擎或检查影片文件是否完整。';
    }
    return '加载内容时遇到一点小问题，请检查网络连接或稍后重试。';
  }

  /**
   * Pre-routes a MediaItem to 'native_hw' (OH_AVPlayer hardware decoding) or 'ffmpeg_sw' (@ohos/ijkplayer)
   * using the `hardwareSupportedFormats` whitelist so unsupported containers/codecs (AVI, XviD, RMVB,
   * MKV with DTS/TrueHD/AC3) open directly in FFmpeg without a mid-open fallback flicker.
   */
  static selectDecodeEngine(
    item: MediaItem,
    preferHardwareDecode: boolean,
    hardwareSupportedFormats?: string[]
  ): DecodeRoutingDecision {
    if (!preferHardwareDecode) {
      return {
        engine: 'ffmpeg_sw',
        matchedFormat: 'manual_sw',
        reason: '已设置为全局优先 FFmpeg 软解'
      };
    }

    const supported = (hardwareSupportedFormats && hardwareSupportedFormats.length > 0)
      ? hardwareSupportedFormats.map(f => f.toLowerCase())
      : AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS;

    const hasFmt = (fmt: string): boolean => {
      const target = fmt.toLowerCase();
      for (let i = 0; i < supported.length; i++) {
        if (supported[i] === target) return true;
      }
      return false;
    };

    const rawName = (item.fileName || item.remotePath || item.streamUrl || '').toLowerCase();
    const rawTitle = `${item.title || ''} ${item.qualityTag || ''} ${rawName}`.toLowerCase();

    // 1. Check explicit software-only audio/video codec tokens in release filename
    if (!hasFmt('dts') && (
      rawTitle.includes('dts') ||
      rawTitle.includes('truehd') ||
      rawTitle.includes('atmos') ||
      rawTitle.includes('eac3') ||
      rawTitle.includes('ddp5') ||
      rawTitle.includes('ac3')
    )) {
      return {
        engine: 'ffmpeg_sw',
        matchedFormat: 'dts',
        reason: '检测到多声道影院音轨 (DTS/AC3/TrueHD)，直连 FFmpeg 软解'
      };
    }

    if (!hasFmt('avi') && (rawTitle.includes('xvid') || rawTitle.includes('divx') || rawName.endsWith('.avi'))) {
      return {
        engine: 'ffmpeg_sw',
        matchedFormat: 'avi',
        reason: 'AVI / XviD 编码不在硬解列表，直连 FFmpeg 软解'
      };
    }

    if (!hasFmt('av1') && (rawTitle.includes('av1') || rawTitle.includes('vp9'))) {
      return {
        engine: 'ffmpeg_sw',
        matchedFormat: 'av1',
        reason: 'AV1 / VP9 编码不在硬解列表，直连 FFmpeg 软解'
      };
    }

    // 2. Extract container extension from fileName / remotePath / streamUrl
    const cleanPath = rawName.split('?')[0].split('#')[0];
    const dot = cleanPath.lastIndexOf('.');
    let ext = dot >= 0 ? cleanPath.substring(dot + 1) : '';
    if (ext === 'm4v') ext = 'mp4';
    if (ext === 'ts' || ext === 'm2ts') ext = 'm3u8';
    if (ext === 'flv' || ext === 'mpg' || ext === 'mpeg') ext = 'rmvb';

    // Network streams without file extensions (Douyin / YouTube / Plex part stream) default to MP4/HLS
    if (!ext || ext.length > 5 || cleanPath.includes('/play/') || cleanPath.includes('part.mp4')) {
      ext = 'mp4';
    }

    if (hasFmt(ext)) {
      return {
        engine: 'native_hw',
        matchedFormat: ext,
        reason: `格式 (${ext.toUpperCase()}) 命中 hardwareSupportedFormats 硬解白名单`
      };
    }

    return {
      engine: 'ffmpeg_sw',
      matchedFormat: ext,
      reason: `封装 (${ext.toUpperCase()}) 未列入硬解白名单，直连 FFmpeg 软解`
    };
  }

  /** Maps a subtitle filename or ISO language tag into a normalized { lang, label } pair. */
  static detectSubtitleLanguage(nameOrLang: string, fallbackIdx: number = 0): SubtitleTrackOption {
    const lower = (nameOrLang || '').toLowerCase();
    const dotParts = lower.replace(/\.[^.]+$/, '').split(/[._\-\s]+/);
    const lastToken = dotParts.length > 0 ? dotParts[dotParts.length - 1] : lower;
    const matchToken = (tokens: string[]): boolean => {
      for (let i = 0; i < tokens.length; i++) {
        if (lastToken === tokens[i] || lower.includes(`.${tokens[i]}.`) || lower === tokens[i]) return true;
      }
      return false;
    };

    if (matchToken(['zh', 'zho', 'chi', 'chs', 'cht', 'cn', 'sc', 'tc', '中文', '简中', '繁中', '简体', '繁体'])) {
      return { lang: 'zh', label: lower.includes('cht') || lower.includes('tc') || lower.includes('繁') ? '繁体中文' : '中文', url: '' };
    }
    if (matchToken(['en', 'eng', 'english', '英文', '英语'])) {
      return { lang: 'en', label: '英文', url: '' };
    }
    if (matchToken(['fr', 'fra', 'fre', 'french', '法文', '法语'])) {
      return { lang: 'fr', label: '法文', url: '' };
    }
    if (matchToken(['ja', 'jpn', 'jp', 'japanese', '日文', '日语'])) {
      return { lang: 'ja', label: '日文', url: '' };
    }
    if (matchToken(['ko', 'kor', 'kr', 'korean', '韩文', '韩语'])) {
      return { lang: 'ko', label: '韩文', url: '' };
    }
    if (matchToken(['es', 'spa', 'spanish', '西班牙语'])) {
      return { lang: 'es', label: '西班牙语', url: '' };
    }
    if (matchToken(['de', 'deu', 'ger', 'german', '德文', '德语'])) {
      return { lang: 'de', label: '德语', url: '' };
    }
    if (matchToken(['ru', 'rus', 'russian', '俄语'])) {
      return { lang: 'ru', label: '俄语', url: '' };
    }
    return {
      lang: `track_${fallbackIdx + 1}`,
      label: nameOrLang && nameOrLang.length <= 16 ? nameOrLang : `外挂字幕 ${fallbackIdx + 1}`,
      url: ''
    };
  }
}

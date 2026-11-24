import { ProxyStreamConfig } from 'libprismplayer.so';
import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry, parseSourceExtra } from '../common/Types';
import { DouyinClient } from './DouyinClient';
import { EmbyClient } from './EmbyClient';
import { IptvClient } from './IptvClient';
import { LocalFileClient } from './LocalFileClient';
import { PlexClient } from './PlexClient';
import { S3Client } from './S3Client';
import { SmbClient } from './SmbClient';
import { WebDavClient, WebDavTestResult } from './WebDavClient';
import { YouTubeClient } from './YouTubeClient';

export interface ResolvedPlayableStream {
  streamUrl: string;
  subtitleUrl: string;
  qualityTag?: string;
}

export class RemoteSourceClient {
  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    if (source.type === 'local') return LocalFileClient.testConnection(source);
    if (source.type === 'smb') return SmbClient.testConnection(source);
    if (source.type === 'plex') return PlexClient.testConnection(source);
    if (source.type === 'emby') return EmbyClient.testConnection(source);
    if (source.type === 's3') return S3Client.testConnection(source);
    if (source.type === 'youtube') return YouTubeClient.testConnection(source);
    if (source.type === 'douyin') return DouyinClient.testConnection(source);
    if (source.type === 'iptv') return IptvClient.testConnection(source);
    return WebDavClient.testConnection(source);
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    let entries: RemoteFileEntry[] = [];
    if (source.type === 'local') {
      entries = await LocalFileClient.listDirectory(source, dirPath);
    } else if (source.type === 'smb') {
      entries = await SmbClient.listDirectory(source, dirPath);
    } else if (source.type === 'plex') {
      entries = await PlexClient.listDirectory(source, dirPath);
    } else if (source.type === 'emby') {
      entries = await EmbyClient.listDirectory(source, dirPath);
    } else if (source.type === 's3') {
      entries = await S3Client.listDirectory(source, dirPath);
    } else if (source.type === 'youtube') {
      entries = await YouTubeClient.listDirectory(source, dirPath);
    } else if (source.type === 'douyin') {
      entries = await DouyinClient.listDirectory(source, dirPath);
    } else if (source.type === 'iptv') {
      entries = await IptvClient.listDirectory(source, dirPath);
    } else {
      entries = await WebDavClient.listDirectory(source, dirPath);
    }
    // 远端各协议只标了视频/字幕；音乐与图片统一在这里补齐，目录页与扫描才有音频入口
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (e.isDirectory) continue;
      if (e.isAudio === undefined) e.isAudio = Formatters.isAudioFile(e.name);
      if (e.isImage === undefined) e.isImage = Formatters.isImageFile(e.name);
    }
    return entries;
  }

  static async fetchText(urlOrPath: string, source?: MediaSource): Promise<string> {
    if (source && source.type === 'local') {
      return LocalFileClient.readText(urlOrPath);
    }
    if (source && source.type === 'smb') {
      return SmbClient.fetchText(urlOrPath, source);
    }
    if (source && (source.type === 's3' || urlOrPath.startsWith('s3://'))) {
      return S3Client.fetchText(urlOrPath, source);
    }
    if (source && source.type === 'plex') {
      return PlexClient.fetchText(urlOrPath, source);
    }
    return WebDavClient.fetchText(urlOrPath, source);
  }

  /** 取二进制图片（海报等）：SMB 走原生字节读，其余走 WebDAV range 读。 */
  static async fetchImageBytes(url: string, source?: MediaSource): Promise<ArrayBuffer> {
    if (source && source.type === 'smb') {
      return SmbClient.fetchBytes(url, source);
    }
    const res = await WebDavClient.fetchRangeChunkForNative(url, '', 0, 16 * 1024 * 1024 - 1, false);
    return res.data;
  }

  /**
   * Resolves dynamic/ephemeral stream URLs right before playback starts:
   * - S3: generates a fresh 12-hour AWS SigV4 Presigned GET URL for video and subtitles
   * - YouTube: resolves fresh direct MP4/HLS stream and auto-captions from videoId/mirror
   */
  static async resolvePlayableStream(item: MediaItem, source?: MediaSource): Promise<ResolvedPlayableStream> {
    // 本机源 / 本地文件直接返回路径，不能再当作 S3/YouTube/抖音 远端地址解析
    const url = item.streamUrl;
    if (url.startsWith('/') || url.startsWith('file://') ||
      url.startsWith('content://') || url.startsWith('datashare://')) {
      return {
        streamUrl: url,
        subtitleUrl: item.subtitleUrl
      };
    }

    if (source && (source.type === 's3' || item.streamUrl.startsWith('s3://'))) {
      const signedVideo = S3Client.resolvePlayUrl(item.streamUrl, source);
      const signedSub = item.subtitleUrl ? S3Client.resolvePlayUrl(item.subtitleUrl, source) : '';
      return {
        streamUrl: signedVideo,
        subtitleUrl: signedSub
      };
    }

    if ((source && source.type === 'youtube') || item.streamUrl.startsWith('youtube://')) {
      const resolved = await YouTubeClient.resolvePlayableStream(item.streamUrl, source);
      return {
        streamUrl: resolved.streamUrl,
        subtitleUrl: item.subtitleUrl || resolved.subtitleUrl,
        qualityTag: resolved.qualityTag
      };
    }

    if (
      item.streamUrl.includes('v.douyin.com') ||
      item.streamUrl.includes('iesdouyin.com/share') ||
      item.streamUrl.startsWith('douyin://')
    ) {
      const dy = await DouyinClient.resolveShareLink(item.streamUrl, source);
      return {
        streamUrl: dy.playUrl,
        subtitleUrl: item.subtitleUrl,
        qualityTag: '抖音无水印'
      };
    }

    return {
      streamUrl: item.streamUrl,
      subtitleUrl: item.subtitleUrl
    };
  }

  /**
   * 判断播放地址是否需要走本地 Range Proxy。
   * 本机文件是绝对路径，即使条目的 source 仍是 SMB/WebDAV 也不能套代理，
   * 否则 C++ 代理会把本地路径当远端打开，返回 502。
   */
  static needsRangeProxy(playUrl: string, source?: MediaSource): boolean {
    const lower = (playUrl || '').toLowerCase();
    const isHttp = lower.startsWith('http://') || lower.startsWith('https://');
    return lower.startsWith('smb://') ||
      (isHttp && source !== undefined &&
        (source.type === 'webdav' || source.type === 'alist' || source.type === 'smb'));
  }

  static buildProxyConfig(streamUrl: string, source?: MediaSource): ProxyStreamConfig {
    if (streamUrl.toLowerCase().startsWith('smb://') || source?.type === 'smb') {
      const cfg: ProxyStreamConfig = {
        url: streamUrl,
        authHeader: '',
        allowInsecureTls: false,
        cacheAlist302: false
      };
      if (source) {
        const parsed = SmbClient.parseSource(source);
        cfg.smbHost = parsed.host;
        cfg.smbPort = parsed.port;
        cfg.smbShare = parsed.share;
        cfg.smbPath = SmbClient.extractRelPathFromUrl(source, streamUrl);
        cfg.smbUser = parsed.username;
        cfg.smbPass = parsed.password;
      }
      return cfg;
    }

    const extra = parseSourceExtra(source?.extraConfig);
    const usesBasicAuth = source && (source.type === 'webdav' || source.type === 'alist') && source.username;
    const isDouyinUrl = source?.type === 'douyin' || streamUrl.includes('snssdk.com') || streamUrl.includes('douyin') || streamUrl.includes('zjcdn.com');
    const defaultUa = isDouyinUrl ? DouyinClient.MOBILE_UA : undefined;
    return {
      url: streamUrl,
      authHeader: usesBasicAuth ? Formatters.buildBasicAuthHeader(source!.username, source!.password) : '',
      userAgent: extra.userAgent || defaultUa,
      allowInsecureTls: source ? source.allowInsecureTls : isDouyinUrl,
      cacheAlist302: source ? source.cacheAlist302 : true
    };
  }
}

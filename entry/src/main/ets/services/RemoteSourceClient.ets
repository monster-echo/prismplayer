import { ProxyStreamConfig } from 'libprismplayer.so';
import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry, parseSourceExtra } from '../common/Types';
import { DouyinClient } from './DouyinClient';
import { EmbyClient } from './EmbyClient';
import { IptvClient } from './IptvClient';
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
    if (source.type === 'smb') return SmbClient.listDirectory(source, dirPath);
    if (source.type === 'plex') return PlexClient.listDirectory(source, dirPath);
    if (source.type === 'emby') return EmbyClient.listDirectory(source, dirPath);
    if (source.type === 's3') return S3Client.listDirectory(source, dirPath);
    if (source.type === 'youtube') return YouTubeClient.listDirectory(source, dirPath);
    if (source.type === 'douyin') return DouyinClient.listDirectory(source, dirPath);
    if (source.type === 'iptv') return IptvClient.listDirectory(source, dirPath);
    return WebDavClient.listDirectory(source, dirPath);
  }

  static async fetchText(urlOrPath: string, source?: MediaSource): Promise<string> {
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
    // 已离线保存的条目直接返回本地路径，不能再当作 S3/YouTube/抖音 远端地址解析
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
   * 已离线保存的条目 streamUrl 是沙箱路径，即使仍挂着 SMB/WebDAV 片源也不能套代理，
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

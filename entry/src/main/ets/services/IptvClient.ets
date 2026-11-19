import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry, parseSourceExtra } from '../common/Types';
import { HttpHelper } from './HttpHelper';
import { WebDavTestResult } from './WebDavClient';

export interface IptvChannelEntry {
  name: string;
  group: string;
  logo: string;
  url: string;
}

interface IptvPayloadResult {
  kind: 'm3u' | 'html' | 'direct';
  text: string;
  url: string;
}

export class IptvClient {
  static parseM3uPlaylist(text: string): IptvChannelEntry[] {
    const lines = text.split(/\r?\n/);
    const out: IptvChannelEntry[] = [];
    let pendingName = '';
    let pendingGroup = '全部频道';
    let pendingLogo = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      if (line.startsWith('#EXTINF:')) {
        const comma = line.lastIndexOf(',');
        pendingName = comma >= 0 ? line.substring(comma + 1).trim() : '未命名频道';
        const grp = line.match(/group-title="([^"]*)"/i);
        pendingGroup = grp && grp[1].trim() ? grp[1].trim() : '全部频道';
        const logo = line.match(/tvg-logo="([^"]*)"/i);
        pendingLogo = logo ? logo[1].trim() : '';
      } else if (!line.startsWith('#') && /^https?:\/\//i.test(line)) {
        out.push({
          name: pendingName || IptvClient.extractFilename(line),
          group: pendingGroup,
          logo: pendingLogo,
          url: line
        });
        pendingName = '';
        pendingGroup = '全部频道';
        pendingLogo = '';
      }
    }
    return out;
  }

  private static extractFilename(url: string): string {
    const clean = url.split('?')[0].replace(/\/+$/, '');
    const slash = clean.lastIndexOf('/');
    const tail = slash >= 0 ? clean.substring(slash + 1) : clean;
    try {
      return decodeURIComponent(tail) || '网络流媒体';
    } catch (_e) {
      return tail || '网络流媒体';
    }
  }

  static parseHtmlDirectoryIndex(html: string, baseUrl: string): RemoteFileEntry[] {
    const cleanBase = baseUrl.replace(/\/+$/, '');
    const out: RemoteFileEntry[] = [];
    const seen = new Set<string>();
    const rx = /<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
    let m: RegExpExecArray | null = rx.exec(html);
    while (m !== null) {
      const href = m[1].trim();
      const label = m[2].replace(/<[^>]+>/g, '').trim();
      if (!href || href === '../' || href === '/' || href.startsWith('?') || href.startsWith('#')) {
        m = rx.exec(html);
        continue;
      }
      const isDir = href.endsWith('/');
      const absUrl = /^https?:\/\//i.test(href)
        ? href
        : (href.startsWith('/') ? `${cleanBase.match(/^https?:\/\/[^/]+/i)?.[0] || ''}${href}` : `${cleanBase}/${href}`);
      if (!seen.has(absUrl)) {
        seen.add(absUrl);
        const name = (label && label !== '../' ? label : IptvClient.extractFilename(href)).replace(/\/+$/, '');
        const isVid = !isDir && (Formatters.isVideoFile(name) || name.toLowerCase().endsWith('.m3u8'));
        const isSub = !isDir && Formatters.isSubtitleFile(name);
        if (isDir || isVid || isSub) {
          out.push({
            name,
            path: absUrl,
            fullUrl: absUrl,
            isDirectory: isDir,
            size: 0,
            lastModified: isDir ? '目录' : 'HTTP 流',
            contentType: isDir ? 'inode/directory' : 'video/mp4',
            isVideo: isVid,
            isSubtitle: isSub
          });
        }
      }
      m = rx.exec(html);
    }
    return out;
  }

  private static async fetchSourcePayload(source: MediaSource, dirPath: string): Promise<IptvPayloadResult> {
    const targetUrl = (dirPath && /^https?:\/\//i.test(dirPath)) ? dirPath : source.baseUrl.trim();
    const extra = parseSourceExtra(source.extraConfig);
    const lowerUrl = targetUrl.toLowerCase().split('?')[0];
    if (lowerUrl.endsWith('.m3u8') || Formatters.isVideoFile(lowerUrl)) {
      return { kind: 'direct', text: '', url: targetUrl };
    }
    const headers: Record<string, string> = {};
    if (extra.userAgent) headers['User-Agent'] = extra.userAgent;
    if (extra.referer) headers['Referer'] = extra.referer;
    const resp = await HttpHelper.requestText(targetUrl, {
      allowInsecureTls: source.allowInsecureTls,
      timeoutMs: 10000,
      headers
    });
    if (resp.statusCode >= 400) {
      throw new Error(`HTTP ${resp.statusCode}：流媒体列表加载失败`);
    }
    if (resp.body.includes('#EXTINF:') || resp.body.trimStart().startsWith('#EXTM3U')) {
      return { kind: 'm3u', text: resp.body, url: targetUrl };
    }
    return { kind: 'html', text: resp.body, url: targetUrl };
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const payload = await IptvClient.fetchSourcePayload(source, '/');
      if (payload.kind === 'direct') {
        return {
          ok: true,
          latencyMs: Date.now() - start,
          entryCount: 1,
          message: '直链视频 / M3U8 流就绪'
        };
      }
      if (payload.kind === 'm3u') {
        const list = IptvClient.parseM3uPlaylist(payload.text);
        return {
          ok: true,
          latencyMs: Date.now() - start,
          entryCount: list.length,
          message: `IPTV / M3U 订阅就绪 · 共 ${list.length} 个频道`
        };
      }
      const entries = IptvClient.parseHtmlDirectoryIndex(payload.text, payload.url);
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: entries.length,
        message: `HTTP 目录索引连接成功 · ${entries.length} 项`
      };
    } catch (e) {
      return {
        ok: false,
        latencyMs: Date.now() - start,
        entryCount: 0,
        message: Formatters.toFriendlyError(e instanceof Error ? e.message : String(e))
      };
    }
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    const norm = (dirPath || '/').trim();
    const payload = await IptvClient.fetchSourcePayload(source, norm);
    if (payload.kind === 'direct') {
      const name = IptvClient.extractFilename(payload.url);
      return [{
        name,
        path: payload.url,
        fullUrl: payload.url,
        isDirectory: false,
        size: 0,
        lastModified: '直播 / 直链流',
        contentType: 'video/mp4',
        isVideo: true,
        isSubtitle: false
      }];
    }
    if (payload.kind === 'm3u') {
      const channels = IptvClient.parseM3uPlaylist(payload.text);
      if (norm.startsWith('/group/')) {
        const grp = norm.substring('/group/'.length);
        return channels.filter(c => c.group === grp).map((c): RemoteFileEntry => ({
          name: c.name,
          path: c.url,
          fullUrl: c.url,
          isDirectory: false,
          size: 0,
          lastModified: c.group,
          contentType: 'application/x-mpegURL',
          isVideo: true,
          isSubtitle: false
        }));
      }
      const groups = new Set<string>();
      for (let i = 0; i < channels.length; i++) {
        groups.add(channels[i].group);
      }
      if (groups.size > 1 && norm === '/') {
        const dirs: RemoteFileEntry[] = [];
        groups.forEach((g) => {
          dirs.push({
            name: g,
            path: `/group/${g}`,
            fullUrl: `/group/${g}`,
            isDirectory: true,
            size: 0,
            lastModified: '频道分组',
            contentType: 'inode/directory',
            isVideo: false,
            isSubtitle: false
          });
        });
        return dirs;
      }
      return channels.map((c): RemoteFileEntry => ({
        name: c.name,
        path: c.url,
        fullUrl: c.url,
        isDirectory: false,
        size: 0,
        lastModified: c.group,
        contentType: 'application/x-mpegURL',
        isVideo: true,
        isSubtitle: false
      }));
    }
    return IptvClient.parseHtmlDirectoryIndex(payload.text, payload.url);
  }

  static async scanLibraryItems(source: MediaSource, maxItems: number): Promise<MediaItem[]> {
    const payload = await IptvClient.fetchSourcePayload(source, '/');
    if (payload.kind === 'direct') {
      const name = IptvClient.extractFilename(payload.url);
      return [{
        id: `${source.id}_direct`,
        sourceId: source.id,
        sourceType: 'iptv',
        remotePath: payload.url,
        streamUrl: payload.url,
        fileName: name,
        fileSize: 0,
        mediaType: 'movie',
        seriesKey: `${source.id}_direct`,
        seriesTitle: source.name,
        seasonNo: 1,
        episodeNo: 0,
        title: source.name || name,
        originalTitle: '',
        year: 0,
        overview: `直链流媒体：${payload.url}`,
        posterUrl: '',
        backdropUrl: '',
        rating: 0,
        qualityTag: payload.url.toLowerCase().includes('.m3u8') ? 'HLS' : 'STREAM',
        tmdbId: 0,
        durationMs: 0,
        subtitleUrl: '',
        addedAt: Date.now()
      }];
    }
    if (payload.kind === 'm3u') {
      const channels = IptvClient.parseM3uPlaylist(payload.text);
      const count = Math.min(maxItems, channels.length);
      const out: MediaItem[] = [];
      for (let i = 0; i < count; i++) {
        const ch = channels[i];
        out.push({
          id: `${source.id}_ch_${i}`,
          sourceId: source.id,
          sourceType: 'iptv',
          remotePath: `/group/${ch.group}/${ch.name}`,
          streamUrl: ch.url,
          fileName: `${ch.name}.m3u8`,
          fileSize: 0,
          mediaType: 'movie',
          seriesKey: `${source.id}_ch_${i}`,
          seriesTitle: ch.group,
          seasonNo: 1,
          episodeNo: 0,
          title: ch.name,
          originalTitle: ch.group,
          year: 0,
          overview: `频道分组：${ch.group}`,
          posterUrl: ch.logo,
          backdropUrl: '',
          rating: 0,
          qualityTag: 'IPTV',
          tmdbId: 0,
          durationMs: 0,
          subtitleUrl: '',
          addedAt: Date.now()
        });
      }
      return out;
    }
    return [];
  }
}

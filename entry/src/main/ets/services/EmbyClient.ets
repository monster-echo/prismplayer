import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry } from '../common/Types';
import { HttpHelper } from './HttpHelper';
import { WebDavTestResult } from './WebDavClient';

interface EmbyAuthUser {
  Id?: string;
}

interface EmbyAuthResp {
  AccessToken?: string;
  User?: EmbyAuthUser;
}

interface EmbyUserItem {
  Id?: string;
  Name?: string;
}

interface EmbyMediaStream {
  Type?: string;
  Index?: number;
  Codec?: string;
}

interface EmbyMediaSourceObj {
  Id?: string;
  Path?: string;
  Size?: number;
  Container?: string;
  MediaStreams?: EmbyMediaStream[];
}

interface EmbyItemObj {
  Id?: string;
  Name?: string;
  OriginalTitle?: string;
  SeriesName?: string;
  Type?: string;
  IsFolder?: boolean;
  Overview?: string;
  ProductionYear?: number;
  CommunityRating?: number;
  RunTimeTicks?: number;
  IndexNumber?: number;
  ParentIndexNumber?: number;
  MediaSources?: EmbyMediaSourceObj[];
}

interface EmbyItemsResp {
  Items?: EmbyItemObj[];
}

export interface EmbySessionContext {
  baseUrl: string;
  token: string;
  userId: string;
}

export class EmbyClient {
  private static sessionCache = new Map<string, EmbySessionContext>();

  static normalizeBaseUrl(rawUrl: string): string {
    let url = (rawUrl || '').trim().replace(/\/+$/, '');
    if (url && !url.startsWith('http://') && !url.startsWith('https://')) {
      url = `http://${url}`;
    }
    return url;
  }

  private static buildAuthHeader(token: string): string {
    return `MediaBrowser Client="PrismPlayer", Device="HarmonyOS", DeviceId="PrismHarmony", Version="1.0.0"${token ? `, Token="${token}"` : ''}`;
  }

  private static async ensureSession(source: MediaSource): Promise<EmbySessionContext> {
    const cached = EmbyClient.sessionCache.get(source.id);
    if (cached && cached.baseUrl === EmbyClient.normalizeBaseUrl(source.baseUrl)) {
      return cached;
    }
    const baseUrl = EmbyClient.normalizeBaseUrl(source.baseUrl);
    let token = '';
    let userId = '';

    if (source.username) {
      const resp = await HttpHelper.requestText(`${baseUrl}/Users/AuthenticateByName`, {
        method: 'POST',
        allowInsecureTls: source.allowInsecureTls,
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization': EmbyClient.buildAuthHeader('')
        },
        body: JSON.stringify({ Username: source.username, Pw: source.password || '' })
      });
      if (resp.statusCode === 401 || resp.statusCode === 403) {
        throw new Error('HTTP 401：Emby / Jellyfin 用户名或密码错误');
      }
      if (resp.statusCode >= 400) {
        throw new Error(`HTTP ${resp.statusCode}：Emby 登录认证失败`);
      }
      const auth = JSON.parse(resp.body) as EmbyAuthResp;
      token = auth.AccessToken || '';
      userId = auth.User?.Id || '';
    } else if (source.password) {
      // Allow API key in password field
      token = source.password.trim();
      const usersResp = await HttpHelper.requestText(`${baseUrl}/Users?api_key=${encodeURIComponent(token)}`, {
        allowInsecureTls: source.allowInsecureTls
      });
      if (usersResp.statusCode === 401) {
        throw new Error('HTTP 401：Emby API Key 无效');
      }
      if (usersResp.statusCode === 200) {
        const list = JSON.parse(usersResp.body) as EmbyUserItem[];
        if (list.length > 0 && list[0].Id) {
          userId = list[0].Id;
        }
      }
    }

    const ctx: EmbySessionContext = { baseUrl, token, userId };
    EmbyClient.sessionCache.set(source.id, ctx);
    return ctx;
  }

  private static async getItemsJson(source: MediaSource, ctx: EmbySessionContext, queryPath: string): Promise<EmbyItemsResp> {
    const sep = queryPath.includes('?') ? '&' : '?';
    const url = `${ctx.baseUrl}${queryPath}${ctx.token ? `${sep}api_key=${encodeURIComponent(ctx.token)}` : ''}`;
    const resp = await HttpHelper.requestText(url, {
      allowInsecureTls: source.allowInsecureTls,
      headers: {
        'Accept': 'application/json',
        'X-Emby-Authorization': EmbyClient.buildAuthHeader(ctx.token)
      }
    });
    if (resp.statusCode === 401) {
      EmbyClient.sessionCache.delete(source.id);
      throw new Error('HTTP 401：Emby 认证会话已失效');
    }
    if (resp.statusCode >= 400) {
      throw new Error(`HTTP ${resp.statusCode}：Emby 目录请求失败`);
    }
    return JSON.parse(resp.body) as EmbyItemsResp;
  }

  static buildStreamUrl(ctx: EmbySessionContext, itemId: string): string {
    const q = ctx.token ? `&api_key=${encodeURIComponent(ctx.token)}` : '';
    return `${ctx.baseUrl}/Videos/${itemId}/stream?Static=true${q}`;
  }

  static buildPosterUrl(ctx: EmbySessionContext, itemId: string): string {
    const q = ctx.token ? `&api_key=${encodeURIComponent(ctx.token)}` : '';
    return `${ctx.baseUrl}/Items/${itemId}/Images/Primary?maxWidth=600${q}`;
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const ctx = await EmbyClient.ensureSession(source);
      const path = ctx.userId ? `/Users/${ctx.userId}/Views` : '/Library/MediaFolders';
      const data = await EmbyClient.getItemsJson(source, ctx, path);
      const count = data.Items ? data.Items.length : 0;
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: count,
        message: `Emby / Jellyfin 连接成功 · 发现 ${count} 个媒体库`
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
    const ctx = await EmbyClient.ensureSession(source);
    const norm = (dirPath || '/').trim();
    let queryPath = ctx.userId ? `/Users/${ctx.userId}/Views` : '/Library/MediaFolders';
    if (norm !== '/' && norm !== '') {
      const parentId = norm.replace(/^\/+|\/+$/g, '');
      queryPath = ctx.userId
        ? `/Users/${ctx.userId}/Items?ParentId=${encodeURIComponent(parentId)}&Fields=MediaSources,Overview,Path`
        : `/Items?ParentId=${encodeURIComponent(parentId)}&Fields=MediaSources,Overview,Path`;
    }
    const resp = await EmbyClient.getItemsJson(source, ctx, queryPath);
    const items = resp.Items || [];
    return items.map((it): RemoteFileEntry => {
      const id = it.Id || '';
      const isDir = !!(it.IsFolder || it.Type === 'CollectionFolder' || it.Type === 'Series' || it.Type === 'Season');
      const ms = it.MediaSources && it.MediaSources.length > 0 ? it.MediaSources[0] : undefined;
      return {
        name: it.Name || id,
        path: `/${id}`,
        fullUrl: isDir ? `/${id}` : EmbyClient.buildStreamUrl(ctx, id),
        isDirectory: isDir,
        size: ms?.Size || 0,
        lastModified: it.RunTimeTicks ? Formatters.formatDuration(Math.round(it.RunTimeTicks / 10000)) : '',
        contentType: isDir ? 'inode/directory' : 'video/mp4',
        isVideo: !isDir,
        isSubtitle: false
      };
    });
  }

  static async scanLibraryItems(source: MediaSource, maxItems: number): Promise<MediaItem[]> {
    const ctx = await EmbyClient.ensureSession(source);
    const query = ctx.userId
      ? `/Users/${ctx.userId}/Items?Recursive=true&IncludeItemTypes=Movie,Episode&Limit=${maxItems}&Fields=MediaSources,Overview,ProductionYear,CommunityRating,RunTimeTicks,SeriesName`
      : `/Items?Recursive=true&IncludeItemTypes=Movie,Episode&Limit=${maxItems}&Fields=MediaSources,Overview,ProductionYear,CommunityRating,RunTimeTicks,SeriesName`;
    const resp = await EmbyClient.getItemsJson(source, ctx, query);
    const list = resp.Items || [];
    const out: MediaItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const m = list[i];
      if (!m.Id || !m.Name) continue;
      const isEp = m.Type === 'Episode';
      const ms = m.MediaSources && m.MediaSources.length > 0 ? m.MediaSources[0] : undefined;
      const durMs = m.RunTimeTicks ? Math.round(m.RunTimeTicks / 10000) : 0;
      out.push({
        id: `${source.id}_emby_${m.Id}`,
        sourceId: source.id,
        sourceType: 'emby',
        remotePath: `/item/${m.Id}`,
        streamUrl: EmbyClient.buildStreamUrl(ctx, m.Id),
        fileName: `${m.Name}.${ms?.Container || 'mkv'}`,
        fileSize: ms?.Size || 0,
        mediaType: isEp ? 'episode' : 'movie',
        seriesKey: isEp && m.SeriesName ? `${source.id}_emby_s_${m.SeriesName.toLowerCase()}` : `${source.id}_emby_${m.Id}`,
        seriesTitle: m.SeriesName || m.Name,
        seasonNo: m.ParentIndexNumber || 1,
        episodeNo: m.IndexNumber || 0,
        title: isEp && m.IndexNumber ? `第 ${m.IndexNumber} 集 · ${m.Name}` : m.Name,
        originalTitle: m.OriginalTitle || '',
        year: m.ProductionYear || 0,
        overview: m.Overview || '',
        posterUrl: EmbyClient.buildPosterUrl(ctx, m.Id),
        backdropUrl: '',
        rating: m.CommunityRating ? Number(m.CommunityRating.toFixed(1)) : 0,
        qualityTag: (ms?.Container || 'HD').toUpperCase(),
        tmdbId: 0,
        durationMs: durMs,
        subtitleUrl: '',
        addedAt: Date.now()
      });
    }
    return out;
  }
}

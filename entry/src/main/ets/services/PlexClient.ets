import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry, SubtitleTrackOption } from '../common/Types';
import { WebDavTestResult } from './WebDavClient';

interface PlexDirectoryObj {
  key?: string;
  type?: string;
  title?: string;
}

interface PlexStreamObj {
  streamType?: number;
  id?: number;
  index?: number;
  codec?: string;
  language?: string;
  languageCode?: string;
  title?: string;
  displayTitle?: string;
  key?: string;
}

interface PlexPartObj {
  key?: string;
  file?: string;
  size?: number;
  container?: string;
  Stream?: PlexStreamObj[];
}

interface PlexMediaObj {
  videoResolution?: string;
  videoCodec?: string;
  container?: string;
  duration?: number;
  Part?: PlexPartObj[];
}

interface PlexMetadataObj {
  ratingKey?: string;
  key?: string;
  type?: string;
  title?: string;
  originalTitle?: string;
  parentTitle?: string;
  grandparentTitle?: string;
  index?: number;
  parentIndex?: number;
  year?: number;
  summary?: string;
  audienceRating?: number;
  rating?: number;
  thumb?: string;
  art?: string;
  duration?: number;
  addedAt?: number;
  Media?: PlexMediaObj[];
}

interface PlexMediaContainer {
  size?: number;
  title1?: string;
  Directory?: PlexDirectoryObj[];
  Metadata?: PlexMetadataObj[];
}

interface PlexRootResp {
  MediaContainer?: PlexMediaContainer;
}

export class PlexClient {
  private static session: rcp.Session | null = null;

  private static getSession(): rcp.Session {
    if (!PlexClient.session) {
      PlexClient.session = rcp.createSession();
    }
    return PlexClient.session;
  }

  static normalizeBaseUrl(rawUrl: string): string {
    let url = rawUrl.trim().replace(/\/+$/, '');
    if (url && !url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://' + url;
    }
    if (!/:\d+$/.test(url) && !url.substring(8).includes(':')) {
      url = `${url}:32400`;
    }
    return url;
  }

  static appendToken(baseUrl: string, pathWithQuery: string, token: string): string {
    const cleanBase = PlexClient.normalizeBaseUrl(baseUrl);
    if (!pathWithQuery) return cleanBase;
    const abs = pathWithQuery.startsWith('http') ? pathWithQuery : `${cleanBase}${pathWithQuery.startsWith('/') ? '' : '/'}${pathWithQuery}`;
    if (!token) return abs;
    const sep = abs.includes('?') ? '&' : '?';
    return `${abs}${sep}X-Plex-Token=${encodeURIComponent(token.trim())}`;
  }

  private static async getJson(source: MediaSource, endpointPath: string): Promise<PlexRootResp> {
    const url = PlexClient.appendToken(source.baseUrl, endpointPath, source.password);
    const req = new rcp.Request(url, 'GET');
    req.headers = {
      'Accept': 'application/json',
      'X-Plex-Client-Identifier': 'PrismPlayerHarmony',
      'X-Plex-Product': 'PrismPlayer'
    };
    if (source.allowInsecureTls) {
      req.configuration = {
        security: { remoteValidation: 'skip' },
        transfer: { timeout: { connectMs: 6000, transferMs: 12000 } }
      };
    } else {
      req.configuration = {
        transfer: { timeout: { connectMs: 6000, transferMs: 12000 } }
      };
    }
    const resp = await PlexClient.getSession().fetch(req);
    if (resp.statusCode === 401) {
      throw new Error('HTTP 401：Plex Token 无效或已过期');
    }
    if (resp.statusCode >= 400) {
      throw new Error(`HTTP ${resp.statusCode}：Plex 接口访问失败`);
    }
    const text = resp.toString() || '{}';
    return JSON.parse(text) as PlexRootResp;
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const json = await PlexClient.getJson(source, '/library/sections');
      const dirs = json.MediaContainer?.Directory || [];
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: dirs.length,
        message: `Plex 连接成功 · 发现 ${dirs.length} 个媒体分区`
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

  private static buildMetadataQuality(meta: PlexMetadataObj): string {
    const media = meta.Media && meta.Media.length > 0 ? meta.Media[0] : undefined;
    if (!media) return '';
    const res = (media.videoResolution || '').toUpperCase();
    const resTag = res === '4K' || res === '2160' ? '4K' : (res ? `${res}P` : '');
    const codec = (media.videoCodec || '').toUpperCase();
    if (resTag && codec) return `${resTag} · ${codec}`;
    return resTag || codec || (media.container || '').toUpperCase();
  }

  private static findSubtitleTracks(source: MediaSource, part: PlexPartObj): SubtitleTrackOption[] {
    const external: SubtitleTrackOption[] = [];
    const embedded: SubtitleTrackOption[] = [];
    if (!part.Stream) return external;
    for (let i = 0; i < part.Stream.length; i++) {
      const s = part.Stream[i];
      if (s.streamType !== 3) continue;
      const codec = (s.codec || '').toLowerCase();
      // PGS/VobSub are bitmap subtitles; they cannot be rendered by the text cue overlay.
      if (codec && !['srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt', 'mov_text', 'text', 'txt'].includes(codec)) {
        continue;
      }
      {
        const streamPath = s.key || (s.id !== undefined ? `/library/streams/${s.id}` : '');
        if (!streamPath) continue;
        const rawTag = s.languageCode || s.language || s.displayTitle || s.title || '';
        const detected = Formatters.detectSubtitleLanguage(rawTag, external.length + embedded.length);
        const track: SubtitleTrackOption = {
          lang: detected.lang,
          label: s.displayTitle || s.language || detected.label,
          url: PlexClient.appendToken(source.baseUrl, streamPath, source.password),
          format: s.codec || ''
        };
        if (s.key) external.push(track);
        else embedded.push(track);
      }
    }
    // External sidecars are directly downloadable; embedded streams may need server transcoding.
    return external.length > 0 ? external : embedded;
  }

  /** Re-read one item's Plex metadata so subtitles added after the library scan are discovered. */
  static async fetchText(url: string, source?: MediaSource): Promise<string> {
    const queryIndex = url.indexOf('?');
    const base = queryIndex >= 0 ? url.substring(0, queryIndex) : url;
    const query = queryIndex >= 0 ? url.substring(queryIndex) : '';
    const variants = [url, `${base}.srt${query}`, `${base}.vtt${query}`, `${url}${query ? '&' : '?'}encoding=utf-8`];
    let lastStatus = 0;
    for (let i = 0; i < variants.length; i++) {
      const req = new rcp.Request(variants[i], 'GET');
      req.headers = {
        'Accept': 'text/plain, */*',
        'X-Plex-Client-Identifier': 'PrismPlayerHarmony',
        'X-Plex-Product': 'PrismPlayer'
      };
      if (source && source.allowInsecureTls) {
        req.configuration = {
          security: { remoteValidation: 'skip' },
          transfer: { timeout: { connectMs: 8000, transferMs: 15000 } }
        };
      }
      const resp = await PlexClient.getSession().fetch(req);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return resp.toString() || '';
      }
      lastStatus = resp.statusCode;
    }
    throw new Error(`HTTP ${lastStatus}`);
  }

  static async probeSubtitleTracks(source: MediaSource, item: MediaItem): Promise<SubtitleTrackOption[]> {
    const prefix = `${source.id}_plex_`;
    if (!item.id.startsWith(prefix)) {
      return [];
    }
    const ratingKey = item.id.substring(prefix.length);
    if (!ratingKey) return [];
    const resp = await PlexClient.getJson(source, `/library/metadata/${ratingKey}?includeStreams=1`);
    const meta = resp.MediaContainer?.Metadata && resp.MediaContainer.Metadata.length > 0
      ? resp.MediaContainer.Metadata[0]
      : undefined;
    const media = meta && meta.Media && meta.Media.length > 0 ? meta.Media[0] : undefined;
    const part = media && media.Part && media.Part.length > 0 ? media.Part[0] : undefined;
    const streams = part && part.Stream ? part.Stream : [];
    hilog.info(0x0001, 'PrismPlex', 'metadata streams=%{public}d', streams.length);
    for (let i = 0; i < streams.length; i++) {
      const s = streams[i];
      if (s.streamType === 3) {
        hilog.info(0x0001, 'PrismPlex', 'sub stream codec=%{public}s key=%{public}s id=%{public}d lang=%{public}s',
          s.codec || '', s.key ? 'yes' : 'no', s.id || 0, s.languageCode || s.language || '');
      }
    }
    return part ? PlexClient.findSubtitleTracks(source, part) : [];
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    const norm = (dirPath || '/').trim();
    const entries: RemoteFileEntry[] = [];

    if (norm === '/' || norm === '') {
      const json = await PlexClient.getJson(source, '/library/sections');
      const dirs = json.MediaContainer?.Directory || [];
      for (let i = 0; i < dirs.length; i++) {
        const d = dirs[i];
        if (!d.key || !d.title) continue;
        entries.push({
          name: `${d.title} (${d.type === 'show' ? '剧集' : '电影'})`,
          path: `/section/${d.key}`,
          fullUrl: '',
          isDirectory: true,
          size: 0,
          lastModified: '',
          contentType: 'httpd/unix-directory',
          isVideo: false,
          isSubtitle: false
        });
      }
      return entries;
    }

    let endpoint = '';
    if (norm.startsWith('/section/')) {
      const secId = norm.substring('/section/'.length);
      endpoint = `/library/sections/${secId}/all`;
    } else if (norm.startsWith('/metadata/')) {
      const rk = norm.substring('/metadata/'.length);
      endpoint = `/library/metadata/${rk}/children`;
    } else {
      endpoint = '/library/sections';
    }

    const json = await PlexClient.getJson(source, endpoint);
    const items = json.MediaContainer?.Metadata || [];
    for (let i = 0; i < items.length; i++) {
      const m = items[i];
      if (!m.ratingKey) continue;
      if (m.type === 'show' || m.type === 'season') {
        entries.push({
          name: m.title || `第 ${m.index || i + 1} 季`,
          path: `/metadata/${m.ratingKey}`,
          fullUrl: '',
          isDirectory: true,
          size: 0,
          lastModified: m.year ? `${m.year}` : '',
          contentType: 'httpd/unix-directory',
          isVideo: false,
          isSubtitle: false
        });
      } else {
        const media = m.Media && m.Media.length > 0 ? m.Media[0] : undefined;
        const part = media && media.Part && media.Part.length > 0 ? media.Part[0] : undefined;
        if (!part || !part.key) continue;
        const rawPath = part.file || `${m.title || 'video'}.${part.container || 'mp4'}`;
        const slash = rawPath.lastIndexOf('/');
        const displayName = m.type === 'episode'
          ? `E${m.index || i + 1} · ${m.title || (slash >= 0 ? rawPath.substring(slash + 1) : rawPath)}`
          : (m.title || (slash >= 0 ? rawPath.substring(slash + 1) : rawPath));
        entries.push({
          name: displayName,
          path: part.file || part.key,
          fullUrl: PlexClient.appendToken(source.baseUrl, part.key, source.password),
          isDirectory: false,
          size: part.size || 0,
          lastModified: m.year ? `${m.year}` : '',
          contentType: 'video/*',
          isVideo: true,
          isSubtitle: false
        });
      }
    }
    return entries;
  }

  static async scanLibraryItems(source: MediaSource, maxItems: number): Promise<MediaItem[]> {
    const out: MediaItem[] = [];
    const secResp = await PlexClient.getJson(source, '/library/sections');
    const sections = secResp.MediaContainer?.Directory || [];

    for (let sIdx = 0; sIdx < sections.length; sIdx++) {
      const sec = sections[sIdx];
      if (!sec.key) continue;
      if (sec.type !== 'movie' && sec.type !== 'show') continue;

      if (sec.type === 'movie') {
        const resp = await PlexClient.getJson(
          source,
          `/library/sections/${sec.key}/all?X-Plex-Container-Start=0&X-Plex-Container-Size=2000`
        );
        const list = resp.MediaContainer?.Metadata || [];
        for (let i = 0; i < list.length && out.length < maxItems; i++) {
          const m = list[i];
          const media = m.Media && m.Media.length > 0 ? m.Media[0] : undefined;
          const part = media && media.Part && media.Part.length > 0 ? media.Part[0] : undefined;
          if (!part || !part.key || !m.ratingKey) continue;
          const filePath = part.file || part.key;
          const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
          const subTracks = PlexClient.findSubtitleTracks(source, part);
          out.push({
            id: `${source.id}_plex_${m.ratingKey}`,
            sourceId: source.id,
            sourceType: 'plex',
            remotePath: filePath,
            streamUrl: PlexClient.appendToken(source.baseUrl, part.key, source.password),
            fileName,
            fileSize: part.size || 0,
            mediaType: 'movie',
            seriesKey: `${source.id}_plex_${m.ratingKey}`,
            seriesTitle: m.title || fileName,
            seasonNo: 1,
            episodeNo: 0,
            title: m.title || fileName,
            originalTitle: m.originalTitle || '',
            year: m.year || 0,
            overview: m.summary || '',
            posterUrl: m.thumb ? PlexClient.appendToken(source.baseUrl, m.thumb, source.password) : '',
            backdropUrl: m.art ? PlexClient.appendToken(source.baseUrl, m.art, source.password) : '',
            rating: m.audienceRating || m.rating || 0,
            qualityTag: PlexClient.buildMetadataQuality(m),
            tmdbId: 0,
            durationMs: m.duration || media?.duration || 0,
            subtitleUrl: subTracks.length > 0 ? subTracks[0].url : '',
            subtitleTracks: subTracks,
            addedAt: (m.addedAt || 0) * 1000 || Date.now()
          });
        }
      } else if (sec.type === 'show') {
        const showsResp = await PlexClient.getJson(
          source,
          `/library/sections/${sec.key}/all?X-Plex-Container-Start=0&X-Plex-Container-Size=2000`
        );
        const shows = showsResp.MediaContainer?.Metadata || [];
        for (let shIdx = 0; shIdx < shows.length && out.length < maxItems; shIdx++) {
          const show = shows[shIdx];
          if (!show.ratingKey) continue;
          const epResp = await PlexClient.getJson(
            source,
            `/library/metadata/${show.ratingKey}/allLeaves?X-Plex-Container-Start=0&X-Plex-Container-Size=2000`
          );
          const eps = epResp.MediaContainer?.Metadata || [];
          const showTitle = show.title || '剧集';
          const showPoster = show.thumb ? PlexClient.appendToken(source.baseUrl, show.thumb, source.password) : '';
          const showArt = show.art ? PlexClient.appendToken(source.baseUrl, show.art, source.password) : '';
          for (let eIdx = 0; eIdx < eps.length && out.length < maxItems; eIdx++) {
            const ep = eps[eIdx];
            const media = ep.Media && ep.Media.length > 0 ? ep.Media[0] : undefined;
            const part = media && media.Part && media.Part.length > 0 ? media.Part[0] : undefined;
            if (!part || !part.key || !ep.ratingKey) continue;
            const filePath = part.file || part.key;
            const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
            const sNo = ep.parentIndex || 1;
            const eNo = ep.index || (eIdx + 1);
            const subTracks = PlexClient.findSubtitleTracks(source, part);
            out.push({
              id: `${source.id}_plex_${ep.ratingKey}`,
              sourceId: source.id,
              sourceType: 'plex',
              remotePath: filePath,
              streamUrl: PlexClient.appendToken(source.baseUrl, part.key, source.password),
              fileName,
              fileSize: part.size || 0,
              mediaType: 'episode',
              seriesKey: `${source.id}_plex_show_${show.ratingKey}`,
              seriesTitle: showTitle,
              seasonNo: sNo,
              episodeNo: eNo,
              title: `第 ${eNo} 集 · ${ep.title || fileName}`,
              originalTitle: show.originalTitle || '',
              year: show.year || ep.year || 0,
              overview: ep.summary || show.summary || '',
              posterUrl: showPoster,
              backdropUrl: showArt,
              rating: show.audienceRating || show.rating || 0,
              qualityTag: PlexClient.buildMetadataQuality(ep),
              tmdbId: 0,
              durationMs: ep.duration || media?.duration || 0,
              subtitleUrl: subTracks.length > 0 ? subTracks[0].url : '',
              subtitleTracks: subTracks,
              addedAt: (ep.addedAt || 0) * 1000 || Date.now()
            });
          }
        }
      }
    }

    return out;
  }
}

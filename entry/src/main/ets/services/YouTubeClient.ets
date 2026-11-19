import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry, parseSourceExtra } from '../common/Types';
import { HttpHelper, HttpTextResponse } from './HttpHelper';
import { WebDavTestResult } from './WebDavClient';

export interface YouTubeTargetInfo {
  kind: 'video' | 'channel' | 'playlist' | 'handle' | 'custom_host';
  id: string;
}

export interface YouTubeVideoSummary {
  videoId: string;
  title: string;
  author: string;
  published: string;
  description: string;
  durationSec: number;
  thumbUrl: string;
}

export interface ResolvedYouTubeStream {
  streamUrl: string;
  subtitleUrl: string;
  qualityTag: string;
  title: string;
  durationMs: number;
}

interface MirrorFormatStream {
  url?: string;
  quality?: string;
  qualityLabel?: string;
  mimeType?: string;
  type?: string;
  videoOnly?: boolean;
  container?: string;
}

interface MirrorSubtitle {
  url?: string;
  label?: string;
  name?: string;
  code?: string;
}

interface MirrorVideoResp {
  url?: string;
  title?: string;
  author?: string;
  uploader?: string;
  lengthSeconds?: number;
  duration?: number;
  hlsUrl?: string;
  hls?: string;
  formatStreams?: MirrorFormatStream[];
  videoStreams?: MirrorFormatStream[];
  captions?: MirrorSubtitle[];
  subtitles?: MirrorSubtitle[];
  videoId?: string;
  id?: string;
}

interface MirrorChannelListResp {
  videos?: MirrorVideoResp[];
  relatedStreams?: MirrorVideoResp[];
}

interface InnerTubePlayerDetails {
  title?: string;
  author?: string;
  lengthSeconds?: string;
  shortDescription?: string;
}

interface InnerTubePlayability {
  status?: string;
  reason?: string;
}

interface InnerTubeCaptionTrack {
  baseUrl?: string;
  languageCode?: string;
}

interface InnerTubeTrackListRenderer {
  captionTracks?: InnerTubeCaptionTrack[];
}

interface InnerTubeCaptions {
  playerCaptionsTracklistRenderer?: InnerTubeTrackListRenderer;
}

interface PickedMirrorStream {
  url: string;
  quality: string;
}

interface InnerTubeStreamingData {
  hlsManifestUrl?: string;
  formats?: MirrorFormatStream[];
}

interface InnerTubePlayerResp {
  playabilityStatus?: InnerTubePlayability;
  videoDetails?: InnerTubePlayerDetails;
  streamingData?: InnerTubeStreamingData;
  captions?: InnerTubeCaptions;
}

export class YouTubeClient {
  private static readonly YT_UA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static parseTarget(rawUrl: string): YouTubeTargetInfo {
    const clean = (rawUrl || '').trim();
    if (!clean) return { kind: 'custom_host', id: '' };

    const ytScheme = clean.match(/^youtube:\/\/(?:watch\?v=)?([A-Za-z0-9_-]{11})/i);
    if (ytScheme) {
      return { kind: 'video', id: ytScheme[1] };
    }
    if (/^[A-Za-z0-9_-]{11}$/.test(clean)) {
      return { kind: 'video', id: clean };
    }

    const vMatch = clean.match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/))([A-Za-z0-9_-]{11})/i);
    if (vMatch) {
      return { kind: 'video', id: vMatch[1] };
    }

    const listMatch = clean.match(/[?&]list=([A-Za-z0-9_-]+)/i);
    if (listMatch) {
      return { kind: 'playlist', id: listMatch[1] };
    }

    const chMatch = clean.match(/youtube\.com\/channel\/(UC[A-Za-z0-9_-]{22})/i);
    if (chMatch) {
      return { kind: 'channel', id: chMatch[1] };
    }

    const handleMatch = clean.match(/youtube\.com\/(@[A-Za-z0-9_.-]+|c\/[A-Za-z0-9_.-]+)/i);
    if (handleMatch) {
      return { kind: 'handle', id: handleMatch[1] };
    }

    return { kind: 'custom_host', id: clean };
  }

  static extractVideoId(urlOrId: string): string {
    const target = YouTubeClient.parseTarget(urlOrId);
    return target.kind === 'video' ? target.id : '';
  }

  private static getMirrorHost(source?: MediaSource): string {
    if (!source) return '';
    const extra = parseSourceExtra(source.extraConfig);
    const mirror = (extra.mirrorUrl || '').trim().replace(/\/+$/, '');
    if (mirror) return mirror;
    const lower = (source.baseUrl || '').toLowerCase();
    if (lower && !lower.includes('youtube.com') && !lower.includes('youtu.be') && lower.startsWith('http')) {
      return source.baseUrl.trim().replace(/\/+$/, '');
    }
    return '';
  }

  private static decodeXmlEntities(text: string): string {
    return text
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
  }

  static parseRssXml(xml: string): YouTubeVideoSummary[] {
    const out: YouTubeVideoSummary[] = [];
    const authorHeaderMatch = xml.match(/<author>\s*<name>([\s\S]*?)<\/name>/);
    const feedAuthor = authorHeaderMatch ? YouTubeClient.decodeXmlEntities(authorHeaderMatch[1].trim()) : 'YouTube';
    const entries = xml.match(/<entry>[\s\S]*?<\/entry>/g) || [];
    for (let i = 0; i < entries.length; i++) {
      const blk = entries[i];
      const idMatch = blk.match(/<yt:videoId>([^<]+)<\/yt:videoId>/);
      const titleMatch = blk.match(/<title>([\s\S]*?)<\/title>/);
      if (!idMatch || !titleMatch) continue;
      const vid = idMatch[1].trim();
      const authorMatch = blk.match(/<author>\s*<name>([\s\S]*?)<\/name>/);
      const pubMatch = blk.match(/<published>([^<]+)<\/published>/);
      const descMatch = blk.match(/<media:description>([\s\S]*?)<\/media:description>/);
      const thumbMatch = blk.match(/<media:thumbnail[^>]*url="([^"]+)"/);

      out.push({
        videoId: vid,
        title: YouTubeClient.decodeXmlEntities(titleMatch[1].trim()),
        author: authorMatch ? YouTubeClient.decodeXmlEntities(authorMatch[1].trim()) : feedAuthor,
        published: pubMatch ? pubMatch[1].substring(0, 10) : '',
        description: descMatch ? YouTubeClient.decodeXmlEntities(descMatch[1].trim()) : '',
        durationSec: 0,
        thumbUrl: thumbMatch ? thumbMatch[1] : `https://i.ytimg.com/vi/${vid}/hqdefault.jpg`
      });
    }
    return out;
  }

  static parseSearchHtml(html: string, maxItems: number = 24): YouTubeVideoSummary[] {
    const out: YouTubeVideoSummary[] = [];
    const seen = new Set<string>();
    const rx = /"videoRenderer"\s*:\s*\{"videoId":"([A-Za-z0-9_-]{11})"[\s\S]{0,1800}?"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)+)"\}/g;
    let m: RegExpExecArray | null = rx.exec(html);
    while (m !== null && out.length < maxItems) {
      const vid = m[1];
      if (!seen.has(vid)) {
        seen.add(vid);
        const title = m[2].replace(/\\"/g, '"').replace(/\\u0026/g, '&');
        out.push({
          videoId: vid,
          title,
          author: 'YouTube 搜索结果',
          published: '',
          description: '',
          durationSec: 0,
          thumbUrl: `https://i.ytimg.com/vi/${vid}/hqdefault.jpg`
        });
      }
      m = rx.exec(html);
    }
    return out;
  }

  private static async resolveChannelIdFromHandle(handleOrUrl: string, insecureTls: boolean): Promise<string> {
    const pageUrl = handleOrUrl.startsWith('http')
      ? handleOrUrl
      : `https://www.youtube.com/${handleOrUrl.replace(/^\/+/, '')}`;
    const resp = await HttpHelper.requestText(pageUrl, {
      allowInsecureTls: insecureTls,
      timeoutMs: 10000,
      headers: { 'User-Agent': YouTubeClient.YT_UA, 'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8' }
    });
    if (resp.statusCode >= 400) {
      throw new Error(`HTTP ${resp.statusCode}：YouTube 频道页面访问失败`);
    }
    const rssMatch = resp.body.match(/feeds\/videos\.xml\?channel_id=(UC[A-Za-z0-9_-]{22})/);
    if (rssMatch) return rssMatch[1];
    const extMatch = resp.body.match(/(?:externalId|channelId|browseId)"\s*:\s*"(UC[A-Za-z0-9_-]{22})"/);
    if (extMatch) return extMatch[1];
    throw new Error('未能从该频道页面识别到 Channel ID');
  }

  private static emptyHttpResp(): HttpTextResponse {
    return { statusCode: 500, body: '' };
  }

  private static async fetchVideosForSource(source: MediaSource, dirPath: string): Promise<YouTubeVideoSummary[]> {
    const mirror = YouTubeClient.getMirrorHost(source);
    const insecure = source.allowInsecureTls;

    if (dirPath.startsWith('/search?q=')) {
      const q = dirPath.substring('/search?q='.length);
      if (mirror) {
        const inv = await HttpHelper.requestText(`${mirror}/api/v1/search?q=${encodeURIComponent(q)}&type=video`, {
          allowInsecureTls: insecure,
          timeoutMs: 10000
        }).catch(() => YouTubeClient.emptyHttpResp());
        if (inv.statusCode === 200 && inv.body.trim().startsWith('[')) {
          const arr = JSON.parse(inv.body) as MirrorVideoResp[];
          return arr.filter(x => !!(x.videoId || x.id)).map((x): YouTubeVideoSummary => {
            const vid = x.videoId || x.id || '';
            return {
              videoId: vid,
              title: x.title || vid,
              author: x.author || x.uploader || 'YouTube',
              published: '',
              description: '',
              durationSec: x.lengthSeconds || x.duration || 0,
              thumbUrl: `https://i.ytimg.com/vi/${vid}/hqdefault.jpg`
            };
          });
        }
      }
      const searchResp = await HttpHelper.requestText(
        `https://www.youtube.com/results?search_query=${encodeURIComponent(q)}`,
        {
          allowInsecureTls: insecure,
          timeoutMs: 10000,
          headers: { 'User-Agent': YouTubeClient.YT_UA, 'Accept-Language': 'en-US,en;q=0.9' }
        }
      );
      return YouTubeClient.parseSearchHtml(searchResp.body);
    }

    const target = YouTubeClient.parseTarget(source.baseUrl);
    if (target.kind === 'video') {
      const meta = await YouTubeClient.fetchWatchPageMetadata(target.id, insecure);
      return [meta];
    }

    if (target.kind === 'playlist') {
      const resp = await HttpHelper.requestText(
        `https://www.youtube.com/feeds/videos.xml?playlist_id=${encodeURIComponent(target.id)}`,
        { allowInsecureTls: insecure, timeoutMs: 10000, headers: { 'User-Agent': YouTubeClient.YT_UA } }
      );
      if (resp.statusCode >= 400) {
        throw new Error(`HTTP ${resp.statusCode}：YouTube 播放列表读取失败`);
      }
      return YouTubeClient.parseRssXml(resp.body);
    }

    if (target.kind === 'channel' || target.kind === 'handle') {
      const channelId = target.kind === 'channel'
        ? target.id
        : await YouTubeClient.resolveChannelIdFromHandle(source.baseUrl, insecure);
      const resp = await HttpHelper.requestText(
        `https://www.youtube.com/feeds/videos.xml?channel_id=${encodeURIComponent(channelId)}`,
        { allowInsecureTls: insecure, timeoutMs: 10000, headers: { 'User-Agent': YouTubeClient.YT_UA } }
      );
      if (resp.statusCode >= 400) {
        throw new Error(`HTTP ${resp.statusCode}：YouTube 频道订阅读取失败`);
      }
      return YouTubeClient.parseRssXml(resp.body);
    }

    // Custom Invidious / Piped Trending or Popular endpoint
    if (mirror) {
      const invPop = await HttpHelper.requestText(`${mirror}/api/v1/popular`, {
        allowInsecureTls: insecure,
        timeoutMs: 10000
      }).catch(() => YouTubeClient.emptyHttpResp());
      if (invPop.statusCode === 200 && invPop.body.trim().startsWith('[')) {
        const arr = JSON.parse(invPop.body) as MirrorVideoResp[];
        return arr.filter(x => !!x.videoId).map((x): YouTubeVideoSummary => ({
          videoId: x.videoId || '',
          title: x.title || x.videoId || '',
          author: x.author || 'YouTube',
          published: '',
          description: '',
          durationSec: x.lengthSeconds || 0,
          thumbUrl: `https://i.ytimg.com/vi/${x.videoId}/hqdefault.jpg`
        }));
      }
      const pipedTrend = await HttpHelper.requestText(`${mirror}/trending?region=US`, {
        allowInsecureTls: insecure,
        timeoutMs: 10000
      }).catch(() => YouTubeClient.emptyHttpResp());
      if (pipedTrend.statusCode === 200 && pipedTrend.body.trim().startsWith('[')) {
        const arr = JSON.parse(pipedTrend.body) as MirrorVideoResp[];
        return arr.map((x): YouTubeVideoSummary => {
          const vid = YouTubeClient.extractVideoId(x.url || x.id || '') || (x.videoId || '');
          return {
            videoId: vid,
            title: x.title || vid,
            author: x.uploader || x.author || 'YouTube',
            published: '',
            description: '',
            durationSec: x.duration || 0,
            thumbUrl: `https://i.ytimg.com/vi/${vid}/hqdefault.jpg`
          };
        }).filter(v => !!v.videoId);
      }
      // Fallback: check channel endpoint on mirror if unused
      const emptyWrap: MirrorChannelListResp = {};
      return emptyWrap.videos ? [] : [];
    }

    throw new Error('请输入有效的 YouTube 视频、@频道、播放列表链接或 Invidious/Piped 实例地址');
  }

  private static async fetchWatchPageMetadata(videoId: string, insecure: boolean): Promise<YouTubeVideoSummary> {
    const resp = await HttpHelper.requestText(`https://www.youtube.com/watch?v=${videoId}`, {
      allowInsecureTls: insecure,
      timeoutMs: 10000,
      headers: { 'User-Agent': YouTubeClient.YT_UA, 'Accept-Language': 'en-US,en;q=0.9' }
    });
    const parsed = YouTubeClient.extractPlayerResponseFromHtml(resp.body);
    const title = parsed?.videoDetails?.title || `YouTube (${videoId})`;
    const author = parsed?.videoDetails?.author || 'YouTube';
    const durSec = parseInt(parsed?.videoDetails?.lengthSeconds || '0', 10) || 0;
    const desc = parsed?.videoDetails?.shortDescription || '';
    return {
      videoId,
      title,
      author,
      published: '',
      description: desc,
      durationSec: durSec,
      thumbUrl: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`
    };
  }

  static extractPlayerResponseFromHtml(html: string): InnerTubePlayerResp | null {
    const m = html.match(/var ytInitialPlayerResponse\s*=\s*(\{.+?\});\s*(?:var |<\/script>)/);
    if (!m) return null;
    try {
      return JSON.parse(m[1]) as InnerTubePlayerResp;
    } catch (_e) {
      return null;
    }
  }

  private static selectMirrorStream(
    streams: MirrorFormatStream[] | undefined,
    qualityPref: string
  ): PickedMirrorStream {
    if (!streams || streams.length === 0) return { url: '', quality: '' };
    const prefNum = parseInt(qualityPref.replace(/[^\d]/g, '') || '1080', 10) || 1080;
    let bestUrl = '';
    let bestScore = -1;
    let bestLabel = 'HD';
    for (let i = 0; i < streams.length; i++) {
      const s = streams[i];
      if (!s.url || s.videoOnly) continue;
      const mime = (s.mimeType || s.type || s.container || '').toLowerCase();
      if (mime && !mime.includes('mp4') && !mime.includes('avc')) continue;
      const qStr = s.qualityLabel || s.quality || '';
      const qNum = parseInt(qStr.replace(/[^\d]/g, '') || '360', 10) || 360;
      const score = qNum <= prefNum ? qNum : (prefNum - (qNum - prefNum) * 0.25);
      if (score > bestScore) {
        bestScore = score;
        bestUrl = s.url;
        bestLabel = qStr || `${qNum}p`;
      }
    }
    return { url: bestUrl, quality: bestLabel };
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const list = await YouTubeClient.fetchVideosForSource(source, '/');
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: list.length,
        message: `YouTube 连接成功 · 获取 ${list.length} 个视频`
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
    const videos = await YouTubeClient.fetchVideosForSource(source, dirPath);
    return videos.map((v): RemoteFileEntry => {
      const durText = v.durationSec > 0 ? Formatters.formatDuration(v.durationSec * 1000) : (v.published || 'YouTube');
      return {
        name: v.title,
        path: `/watch/${v.videoId}`,
        fullUrl: `youtube://watch?v=${v.videoId}`,
        isDirectory: false,
        size: 0,
        lastModified: `${v.author} · ${durText}`,
        contentType: 'video/mp4',
        isVideo: true,
        isSubtitle: false
      };
    });
  }

  static async scanLibraryItems(source: MediaSource, maxItems: number): Promise<MediaItem[]> {
    const videos = await YouTubeClient.fetchVideosForSource(source, '/');
    const items: MediaItem[] = [];
    const count = Math.min(maxItems, videos.length);
    for (let i = 0; i < count; i++) {
      const v = videos[i];
      items.push({
        id: `${source.id}_yt_${v.videoId}`,
        sourceId: source.id,
        sourceType: 'youtube',
        remotePath: `/watch/${v.videoId}`,
        streamUrl: `youtube://watch?v=${v.videoId}`,
        fileName: `${v.title}.mp4`,
        fileSize: 0,
        mediaType: 'movie',
        seriesKey: `${source.id}_yt_${v.videoId}`,
        seriesTitle: v.author,
        seasonNo: 1,
        episodeNo: 0,
        title: v.title,
        originalTitle: v.author,
        year: v.published ? (parseInt(v.published.substring(0, 4), 10) || 0) : 0,
        overview: v.description || `YouTube 频道：${v.author}`,
        posterUrl: v.thumbUrl,
        backdropUrl: `https://i.ytimg.com/vi/${v.videoId}/maxresdefault.jpg`,
        rating: 0,
        qualityTag: 'YouTube',
        tmdbId: 0,
        durationMs: v.durationSec * 1000,
        subtitleUrl: '',
        addedAt: Date.now()
      });
    }
    return items;
  }

  static async resolvePlayableStream(streamUrlOrId: string, source?: MediaSource): Promise<ResolvedYouTubeStream> {
    const videoId = YouTubeClient.extractVideoId(streamUrlOrId);
    if (!videoId) {
      throw new Error('无效的 YouTube 视频 ID');
    }
    const extra = parseSourceExtra(source?.extraConfig);
    const mirror = YouTubeClient.getMirrorHost(source);
    const qualityPref = extra.qualityPref || '1080p';
    const insecure = source ? source.allowInsecureTls : false;

    // 1. Check self-hosted Cobalt / yt-dlp REST / Invidious / Piped mirror first if configured
    if (mirror) {
      // 1a. Cobalt JSON API (POST /)
      const cobaltResp = await HttpHelper.requestText(`${mirror}/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ url: `https://www.youtube.com/watch?v=${videoId}`, videoQuality: qualityPref.replace('p', '') || '1080' }),
        allowInsecureTls: insecure,
        timeoutMs: 10000
      }).catch(() => YouTubeClient.emptyHttpResp());
      if (cobaltResp.statusCode === 200 && cobaltResp.body.includes('"url"')) {
        try {
          const cbData = JSON.parse(cobaltResp.body) as MirrorVideoResp;
          if (cbData.url) {
            return {
              streamUrl: cbData.url,
              subtitleUrl: '',
              qualityTag: qualityPref || 'MP4',
              title: cbData.title || videoId,
              durationMs: 0
            };
          }
        } catch (_e) {
          // Continue
        }
      }

      // 1b. Invidious /api/v1/videos/{id}
      const invResp = await HttpHelper.requestText(`${mirror}/api/v1/videos/${videoId}`, {
        allowInsecureTls: insecure,
        timeoutMs: 10000
      }).catch(() => YouTubeClient.emptyHttpResp());
      if (invResp.statusCode === 200 && invResp.body.includes('"')) {
        const data = JSON.parse(invResp.body) as MirrorVideoResp;
        const picked = YouTubeClient.selectMirrorStream(data.formatStreams, qualityPref);
        const directUrl = picked.url || data.hlsUrl || '';
        if (directUrl) {
          const cap = data.captions && data.captions.length > 0 && data.captions[0].url
            ? (data.captions[0].url.startsWith('http') ? data.captions[0].url : `${mirror}${data.captions[0].url}`)
            : '';
          return {
            streamUrl: directUrl,
            subtitleUrl: cap,
            qualityTag: picked.quality || 'HLS',
            title: data.title || videoId,
            durationMs: (data.lengthSeconds || 0) * 1000
          };
        }
      }

      // 1c. Piped /streams/{id}
      const pipedResp = await HttpHelper.requestText(`${mirror}/streams/${videoId}`, {
        allowInsecureTls: insecure,
        timeoutMs: 10000
      }).catch(() => YouTubeClient.emptyHttpResp());
      if (pipedResp.statusCode === 200 && pipedResp.body.includes('"')) {
        const data = JSON.parse(pipedResp.body) as MirrorVideoResp;
        const picked = YouTubeClient.selectMirrorStream(data.videoStreams, qualityPref);
        const directUrl = picked.url || data.hls || '';
        if (directUrl) {
          const cap = data.subtitles && data.subtitles.length > 0 && data.subtitles[0].url ? data.subtitles[0].url : '';
          return {
            streamUrl: directUrl,
            subtitleUrl: cap,
            qualityTag: picked.quality || 'HLS',
            title: data.title || videoId,
            durationMs: (data.duration || 0) * 1000
          };
        }
      }
    }

    // 2. Native InnerTube ANDROID_VR / IOS client extraction (returns unciphered URLs + HLS without JS cipher)
    const innerClients: string[][] = [
      ['ANDROID_VR', '1.60.19', 'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip'],
      ['IOS', '19.29.1', 'com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)']
    ];
    for (let cIdx = 0; cIdx < innerClients.length; cIdx++) {
      const cName = innerClients[cIdx][0];
      const cVer = innerClients[cIdx][1];
      const cUa = innerClients[cIdx][2];
      const innertubeBody = `{"context":{"client":{"clientName":"${cName}","clientVersion":"${cVer}","hl":"zh-CN","gl":"US"}},"videoId":"${videoId}"}`;
      const itResp = await HttpHelper.requestText('https://www.youtube.com/youtubei/v1/player?prettyPrint=false', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': cUa
        },
        body: innertubeBody,
        allowInsecureTls: insecure,
        timeoutMs: 9000
      }).catch(() => YouTubeClient.emptyHttpResp());
      if (itResp.statusCode === 200 && itResp.body.includes('"streamingData"')) {
        try {
          const player = JSON.parse(itResp.body) as InnerTubePlayerResp;
          if (player.streamingData) {
            let plainUrl = player.streamingData.hlsManifestUrl || '';
            let qTag = plainUrl ? 'HLS' : 'YouTube';
            if (!plainUrl && player.streamingData.formats) {
              for (let i = 0; i < player.streamingData.formats.length; i++) {
                const f = player.streamingData.formats[i];
                if (f.url) {
                  plainUrl = f.url;
                  qTag = f.qualityLabel || 'MP4';
                }
              }
            }
            if (plainUrl) {
              const tracks = player.captions?.playerCaptionsTracklistRenderer?.captionTracks;
              let subUrl = '';
              if (tracks && tracks.length > 0 && tracks[0].baseUrl) {
                subUrl = `${tracks[0].baseUrl}&fmt=vtt`;
              }
              return {
                streamUrl: plainUrl,
                subtitleUrl: subUrl,
                qualityTag: qTag,
                title: player.videoDetails?.title || videoId,
                durationMs: (parseInt(player.videoDetails?.lengthSeconds || '0', 10) || 0) * 1000
              };
            }
          }
        } catch (_e) {
          // Try next client
        }
      }
    }

    // 3. Direct YouTube watch HTML check (plain formats / HLS / captions)
    const watchHeaders: Record<string, string> = {
      'User-Agent': YouTubeClient.YT_UA,
      'Accept-Language': 'en-US,en;q=0.9'
    };
    if (extra.cookie) {
      watchHeaders['Cookie'] = extra.cookie;
    }
    const watchResp = await HttpHelper.requestText(`https://www.youtube.com/watch?v=${videoId}`, {
      allowInsecureTls: insecure,
      timeoutMs: 10000,
      headers: watchHeaders
    });
    const player = YouTubeClient.extractPlayerResponseFromHtml(watchResp.body);
    if (player && player.streamingData) {
      let plainUrl = player.streamingData.hlsManifestUrl || '';
      let qTag = plainUrl ? 'HLS' : 'YouTube';
      if (!plainUrl && player.streamingData.formats) {
        for (let i = 0; i < player.streamingData.formats.length; i++) {
          const f = player.streamingData.formats[i];
          if (f.url) {
            plainUrl = f.url;
            qTag = f.qualityLabel || 'MP4';
          }
        }
      }
      if (plainUrl) {
        const tracks = player.captions?.playerCaptionsTracklistRenderer?.captionTracks;
        let subUrl = '';
        if (tracks && tracks.length > 0 && tracks[0].baseUrl) {
          subUrl = `${tracks[0].baseUrl}&fmt=vtt`;
        }
        return {
          streamUrl: plainUrl,
          subtitleUrl: subUrl,
          qualityTag: qTag,
          title: player.videoDetails?.title || videoId,
          durationMs: (parseInt(player.videoDetails?.lengthSeconds || '0', 10) || 0) * 1000
        };
      }
    }

    throw new Error('YouTube 当前视频流需要签名解密，请在片源编辑中添加自建 Invidious / Piped 镜像服务地址。');
  }
}

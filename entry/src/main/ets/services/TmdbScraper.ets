import { rcp } from '@kit.RemoteCommunicationKit';
import { AppConstants } from '../common/Constants';
import { AppSettings, MediaItem } from '../common/Types';

interface TmdbSearchEntry {
  id: number;
  title?: string;
  name?: string;
  original_title?: string;
  original_name?: string;
  overview?: string;
  poster_path?: string;
  backdrop_path?: string;
  vote_average?: number;
  release_date?: string;
  first_air_date?: string;
}

interface TmdbSearchResponse {
  results?: TmdbSearchEntry[];
}

interface ItunesMovieEntry {
  trackName?: string;
  artworkUrl100?: string;
  longDescription?: string;
  shortDescription?: string;
  releaseDate?: string;
}

interface ItunesSearchResp {
  results?: ItunesMovieEntry[];
}

interface TvMazeRating {
  average?: number;
}

interface TvMazeImage {
  medium?: string;
  original?: string;
}

interface TvMazeShowResp {
  name?: string;
  summary?: string;
  premiered?: string;
  rating?: TvMazeRating;
  image?: TvMazeImage;
}

export interface TmdbCandidate {
  kind: 'movie' | 'tv';
  tmdbId: number;
  title: string;
  originalTitle: string;
  year: number;
  rating: number;
  overview: string;
  posterUrl: string;
  backdropUrl: string;
}

export class TmdbScraper {
  private static session: rcp.Session | null = null;

  private static getSession(): rcp.Session {
    if (!TmdbScraper.session) {
      TmdbScraper.session = rcp.createSession();
    }
    return TmdbScraper.session;
  }

  /**
   * 刮削候选搜索：返回 TMDB 搜索结果全量候选（供刮削面板逐条挑选）。
   * 未配置 Key 时抛错，由面板提示。
   */
  static async searchCandidates(settings: AppSettings, kind: 'movie' | 'tv', query: string): Promise<TmdbCandidate[]> {
    if (!settings.tmdbApiKey) {
      throw new Error('未填写 TMDB API Key，请在「设置 → TMDB 刮削」配置后使用');
    }
    const host = (settings.tmdbApiHost || AppConstants.DEFAULT_TMDB_HOST).replace(/\/+$/, '');
    const imgBase = (settings.tmdbImageBase || AppConstants.DEFAULT_TMDB_IMAGE_BASE).replace(/\/+$/, '');
    const url = `${host}/search/${kind}?api_key=${encodeURIComponent(settings.tmdbApiKey)}&language=zh-CN&query=${encodeURIComponent(query)}`;
    const req = new rcp.Request(url, 'GET', { 'accept': 'application/json' });
    req.configuration = { transfer: { timeout: { connectMs: 6000, transferMs: 8000 } } };
    const resp = await TmdbScraper.getSession().fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`TMDB 搜索失败（${resp.statusCode}）`);
    }
    const parsed = JSON.parse(resp.toString() || '{}') as TmdbSearchResponse;
    const results = parsed.results || [];
    const candidates: TmdbCandidate[] = [];
    for (let i = 0; i < results.length; i++) {
      const hit = results[i];
      const dateStr = hit.release_date || hit.first_air_date || '';
      candidates.push({
        kind,
        tmdbId: hit.id,
        title: hit.title || hit.name || '',
        originalTitle: hit.original_title || hit.original_name || '',
        year: dateStr.length >= 4 ? (parseInt(dateStr.substring(0, 4), 10) || 0) : 0,
        rating: typeof hit.vote_average === 'number' ? Number(hit.vote_average.toFixed(1)) : 0,
        overview: hit.overview || '',
        posterUrl: hit.poster_path ? `${imgBase}${hit.poster_path}` : '',
        backdropUrl: hit.backdrop_path ? `${imgBase.replace('/w500', '/w780')}${hit.backdrop_path}` : ''
      });
    }
    return candidates;
  }

  /** 把选中的刮削候选应用到条目（字段映射与 enrichItem 一致）。 */
  static applyCandidate(item: MediaItem, settings: AppSettings, cand: TmdbCandidate): MediaItem {
    return {
      id: item.id,
      sourceId: item.sourceId,
      sourceType: item.sourceType,
      remotePath: item.remotePath,
      streamUrl: item.streamUrl,
      fileName: item.fileName,
      fileSize: item.fileSize,
      mediaType: item.mediaType,
      seriesKey: item.seriesKey,
      seriesTitle: item.mediaType === 'episode' ? cand.title : item.seriesTitle,
      seasonNo: item.seasonNo,
      episodeNo: item.episodeNo,
      title: item.mediaType === 'episode' ? item.title : cand.title,
      originalTitle: cand.originalTitle || item.originalTitle,
      year: cand.year || item.year,
      overview: cand.overview || item.overview,
      posterUrl: cand.posterUrl || item.posterUrl,
      backdropUrl: cand.backdropUrl || item.backdropUrl,
      rating: cand.rating > 0 ? cand.rating : item.rating,
      qualityTag: item.qualityTag,
      tmdbId: cand.tmdbId || item.tmdbId,
      durationMs: item.durationMs,
      subtitleUrl: item.subtitleUrl,
      subtitleTracks: item.subtitleTracks,
      isFavorite: item.isFavorite,
      addedAt: item.addedAt
    };
  }

  static async enrichItem(item: MediaItem, settings: AppSettings): Promise<MediaItem> {
    if (!settings.tmdbApiKey) {
      return await TmdbScraper.enrichPublicFallback(item);
    }
    const host = (settings.tmdbApiHost || AppConstants.DEFAULT_TMDB_HOST).replace(/\/+$/, '');
    const imgBase = (settings.tmdbImageBase || AppConstants.DEFAULT_TMDB_IMAGE_BASE).replace(/\/+$/, '');
    const kind = item.mediaType === 'episode' ? 'tv' : 'movie';
    const queryTitle = encodeURIComponent(item.mediaType === 'episode' ? item.seriesTitle : item.title);
    let url = `${host}/search/${kind}?api_key=${encodeURIComponent(settings.tmdbApiKey)}&language=zh-CN&query=${queryTitle}`;
    if (item.year > 0) {
      url += kind === 'movie' ? `&year=${item.year}` : `&first_air_date_year=${item.year}`;
    }

    try {
      const req = new rcp.Request(url, 'GET', { 'accept': 'application/json' });
      req.configuration = {
        transfer: {
          timeout: { connectMs: 6000, transferMs: 8000 }
        }
      };
      const resp = await TmdbScraper.getSession().fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return item;
      }
      const parsed = JSON.parse(resp.toString() || '{}') as TmdbSearchResponse;
      if (!parsed.results || parsed.results.length === 0) {
        return item;
      }
      const hit = parsed.results[0];
      const updatedTitle = hit.title || hit.name || item.title;
      const updatedOrig = hit.original_title || hit.original_name || item.originalTitle;
      const dateStr = hit.release_date || hit.first_air_date || '';
      const parsedYear = dateStr.length >= 4 ? (parseInt(dateStr.substring(0, 4), 10) || item.year) : item.year;

      return {
        id: item.id,
        sourceId: item.sourceId,
        sourceType: item.sourceType,
        remotePath: item.remotePath,
        streamUrl: item.streamUrl,
        fileName: item.fileName,
        fileSize: item.fileSize,
        mediaType: item.mediaType,
        seriesKey: item.seriesKey,
        seriesTitle: item.mediaType === 'episode' ? updatedTitle : item.seriesTitle,
        seasonNo: item.seasonNo,
        episodeNo: item.episodeNo,
        title: item.mediaType === 'episode' ? item.title : updatedTitle,
        originalTitle: updatedOrig,
        year: parsedYear,
        overview: hit.overview || item.overview,
        posterUrl: hit.poster_path ? `${imgBase}${hit.poster_path}` : item.posterUrl,
        backdropUrl: hit.backdrop_path ? `${imgBase.replace('/w500', '/w780')}${hit.backdrop_path}` : item.backdropUrl,
        rating: typeof hit.vote_average === 'number' ? Number(hit.vote_average.toFixed(1)) : item.rating,
        qualityTag: item.qualityTag,
        tmdbId: hit.id || item.tmdbId,
        durationMs: item.durationMs,
        subtitleUrl: item.subtitleUrl,
        subtitleTracks: item.subtitleTracks,
        isFavorite: item.isFavorite,
        addedAt: item.addedAt
      };
    } catch (_e) {
      return item;
    }
  }

  /**
   * Keyless public metadata fallback (TVMaze for series, iTunes Search API for movies)
   * so posters, years, and synopses populate out of the box even without a TMDB API Key.
   */
  private static async enrichPublicFallback(item: MediaItem): Promise<MediaItem> {
    const queryRaw = (item.mediaType === 'episode' ? item.seriesTitle : item.title).trim();
    if (!queryRaw) return item;
    try {
      if (item.mediaType === 'episode') {
        const url = `https://api.tvmaze.com/singlesearch/shows?q=${encodeURIComponent(queryRaw)}`;
        const req = new rcp.Request(url, 'GET', { 'accept': 'application/json' });
        req.configuration = { transfer: { timeout: { connectMs: 4000, transferMs: 6000 } } };
        const resp = await TmdbScraper.getSession().fetch(req);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          const show = JSON.parse(resp.toString() || '{}') as TvMazeShowResp;
          const poster = show.image?.original || show.image?.medium || item.posterUrl;
          const cleanSummary = (show.summary || '').replace(/<[^>]+>/g, '').trim();
          const year = show.premiered && show.premiered.length >= 4
            ? (parseInt(show.premiered.substring(0, 4), 10) || item.year)
            : item.year;
          return {
            id: item.id,
            sourceId: item.sourceId,
            sourceType: item.sourceType,
            remotePath: item.remotePath,
            streamUrl: item.streamUrl,
            fileName: item.fileName,
            fileSize: item.fileSize,
            mediaType: item.mediaType,
            seriesKey: item.seriesKey,
            seriesTitle: show.name || item.seriesTitle,
            seasonNo: item.seasonNo,
            episodeNo: item.episodeNo,
            title: item.title,
            originalTitle: item.originalTitle,
            year,
            overview: cleanSummary || item.overview,
            posterUrl: poster,
            backdropUrl: poster || item.backdropUrl,
            rating: show.rating?.average || item.rating,
            qualityTag: item.qualityTag,
            tmdbId: item.tmdbId,
            durationMs: item.durationMs,
            subtitleUrl: item.subtitleUrl,
            subtitleTracks: item.subtitleTracks,
            isFavorite: item.isFavorite,
            addedAt: item.addedAt
          };
        }
      } else {
        const url = `https://itunes.apple.com/search?term=${encodeURIComponent(queryRaw)}&media=movie&entity=movie&country=cn&limit=1`;
        const req = new rcp.Request(url, 'GET', { 'accept': 'application/json' });
        req.configuration = { transfer: { timeout: { connectMs: 4000, transferMs: 6000 } } };
        const resp = await TmdbScraper.getSession().fetch(req);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          const data = JSON.parse(resp.toString() || '{}') as ItunesSearchResp;
          const hit = data.results && data.results.length > 0 ? data.results[0] : undefined;
          if (hit) {
            const hiRes = (hit.artworkUrl100 || '').replace('100x100bb', '600x600bb');
            const year = hit.releaseDate && hit.releaseDate.length >= 4
              ? (parseInt(hit.releaseDate.substring(0, 4), 10) || item.year)
              : item.year;
            return {
              id: item.id,
              sourceId: item.sourceId,
              sourceType: item.sourceType,
              remotePath: item.remotePath,
              streamUrl: item.streamUrl,
              fileName: item.fileName,
              fileSize: item.fileSize,
              mediaType: item.mediaType,
              seriesKey: item.seriesKey,
              seriesTitle: item.seriesTitle,
              seasonNo: item.seasonNo,
              episodeNo: item.episodeNo,
              title: hit.trackName || item.title,
              originalTitle: item.originalTitle,
              year,
              overview: hit.longDescription || hit.shortDescription || item.overview,
              posterUrl: hiRes || item.posterUrl,
              backdropUrl: hiRes || item.backdropUrl,
              rating: item.rating,
              qualityTag: item.qualityTag,
              tmdbId: item.tmdbId,
              durationMs: item.durationMs,
              subtitleUrl: item.subtitleUrl,
              subtitleTracks: item.subtitleTracks,
              isFavorite: item.isFavorite,
              addedAt: item.addedAt
            };
          }
        }
      }
    } catch (_e) {
      // Ignore fallback errors
    }
    return item;
  }
}

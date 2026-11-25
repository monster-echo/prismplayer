import { MediaItem, SeriesGroup } from '../common/Types';
import { LocalVideoIndex } from './LocalVideoIndex';

export type CatalogSort = 'recent' | 'name' | 'year' | 'rating' | 'duration' | 'episodes';
export type CatalogDecade = 'all' | '2020' | '2010' | '2000' | 'older' | 'unknown';
export type CatalogResolution = 'all' | '4k' | '1080' | '720' | 'other';
export type FavoriteType = 'all' | 'movie' | 'episode';

/**
 * 分类目录页的筛选/排序纯函数。
 *
 * 电影、剧集、收藏共用网格，但筛选维度不同：
 * - 电影：片源、画质、年代、时间/名称/年份/评分/时长
 * - 剧集：片源、年代、时间/名称/年份/评分/集数
 * - 收藏：片源、类型、时间/名称/年份/评分
 * 音乐单独走 MusicLibrary，不在这里。
 */
export class LibraryCatalog {
  static decadeOf(year: number): CatalogDecade {
    if (!year || year <= 0) return 'unknown';
    if (year >= 2020) return '2020';
    if (year >= 2010) return '2010';
    if (year >= 2000) return '2000';
    return 'older';
  }

  static matchesDecade(year: number, decade: CatalogDecade): boolean {
    return decade === 'all' || LibraryCatalog.decadeOf(year) === decade;
  }

  static matchesResolution(item: MediaItem, filter: CatalogResolution): boolean {
    if (filter === 'all') return true;
    const rank = LocalVideoIndex.resolutionRank(item);
    if (filter === '4k') return rank === 4;
    if (filter === '1080') return rank === 3;
    if (filter === '720') return rank === 2;
    return rank <= 1;
  }

  static filterMovies(items: MediaItem[], sourceId: string, resolution: CatalogResolution,
    decade: CatalogDecade): MediaItem[] {
    return items.filter((it: MediaItem) => {
      if (sourceId && it.sourceId !== sourceId) return false;
      if (!LibraryCatalog.matchesResolution(it, resolution)) return false;
      return LibraryCatalog.matchesDecade(it.year, decade);
    });
  }

  static sortItems(items: MediaItem[], sort: CatalogSort): MediaItem[] {
    const out = items.slice();
    out.sort((a: MediaItem, b: MediaItem) => {
      if (sort === 'name') return a.title.localeCompare(b.title, 'zh-CN');
      if (sort === 'year') return (b.year || 0) - (a.year || 0) || (b.addedAt || 0) - (a.addedAt || 0);
      if (sort === 'rating') return (b.rating || 0) - (a.rating || 0) || (b.addedAt || 0) - (a.addedAt || 0);
      if (sort === 'duration') return (b.durationMs || 0) - (a.durationMs || 0);
      return (b.addedAt || 0) - (a.addedAt || 0);
    });
    return out;
  }

  static seriesSourceId(grp: SeriesGroup): string {
    return grp.episodes.length > 0 ? grp.episodes[0].sourceId : '';
  }

  static seriesYear(grp: SeriesGroup): number {
    if (grp.year > 0) return grp.year;
    for (let i = 0; i < grp.episodes.length; i++) {
      if (grp.episodes[i].year > 0) return grp.episodes[i].year;
    }
    return 0;
  }

  static seriesLatestAt(grp: SeriesGroup): number {
    let latest = 0;
    for (let i = 0; i < grp.episodes.length; i++) {
      latest = Math.max(latest, grp.episodes[i].addedAt || 0);
    }
    return latest;
  }

  static filterSeries(groups: SeriesGroup[], sourceId: string, decade: CatalogDecade): SeriesGroup[] {
    return groups.filter((grp: SeriesGroup) => {
      if (sourceId && LibraryCatalog.seriesSourceId(grp) !== sourceId) return false;
      return LibraryCatalog.matchesDecade(LibraryCatalog.seriesYear(grp), decade);
    });
  }

  static sortSeries(groups: SeriesGroup[], sort: CatalogSort): SeriesGroup[] {
    const out = groups.slice();
    out.sort((a: SeriesGroup, b: SeriesGroup) => {
      if (sort === 'name') return a.title.localeCompare(b.title, 'zh-CN');
      if (sort === 'year') return LibraryCatalog.seriesYear(b) - LibraryCatalog.seriesYear(a);
      if (sort === 'rating') return (b.rating || 0) - (a.rating || 0);
      if (sort === 'episodes') return b.episodes.length - a.episodes.length;
      return LibraryCatalog.seriesLatestAt(b) - LibraryCatalog.seriesLatestAt(a);
    });
    return out;
  }

  static filterFavorites(items: MediaItem[], sourceId: string, type: FavoriteType): MediaItem[] {
    return items.filter((it: MediaItem) => {
      if (sourceId && it.sourceId !== sourceId) return false;
      if (type === 'all') return true;
      return it.mediaType === type;
    });
  }
}

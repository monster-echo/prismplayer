import { MediaItem } from '../common/Types';

export type LocalSort = 'recent' | 'name' | 'size' | 'duration' | 'resolution';
export type LocalTypeFilter = 'all' | 'movie' | 'episode';

export interface LocalFolderGroup {
  /** 相对本机根目录的文件夹路径；根目录为空串 */
  path: string;
  name: string;
  items: MediaItem[];
  coverUrl: string;
  totalSize: number;
  latestAt: number;
}

/**
 * 本机视频的目录/排序索引。
 *
 * 本机条目只存文件路径，没有目录表；这里按 remotePath 的父目录分组，
 * 给「本机视频」页提供文件夹视图和排序。纯函数，方便单测。
 */
export class LocalVideoIndex {
  static isLocalVideo(item: MediaItem): boolean {
    return item.sourceType === 'local' && (item.mediaType === 'movie' || item.mediaType === 'episode');
  }

  static pickVideos(items: MediaItem[]): MediaItem[] {
    return items.filter((it: MediaItem) => LocalVideoIndex.isLocalVideo(it));
  }

  private static decode(raw: string): string {
    try {
      return decodeURIComponent(raw);
    } catch (_e) {
      return raw;
    }
  }

  private static normalizeRoot(rootUri: string): string {
    const root = LocalVideoIndex.decode(rootUri || '').replace(/\/+$/, '');
    return root;
  }

  /** 相对根目录的父文件夹路径；根目录下的文件返回空串。 */
  static folderPath(item: MediaItem, rootUri: string): string {
    const full = LocalVideoIndex.decode(item.remotePath || '');
    const root = LocalVideoIndex.normalizeRoot(rootUri);
    let rel = full;
    if (root) {
      if (full === root) return '';
      if (full.startsWith(`${root}/`)) {
        rel = full.substring(root.length + 1);
      }
    }
    const slash = rel.lastIndexOf('/');
    return slash >= 0 ? rel.substring(0, slash) : '';
  }

  /** 文件夹展示名：子目录取最后一段，根目录取根 URI 的最后一段。 */
  static folderLabel(path: string, rootUri: string): string {
    const source = path && path.length > 0 ? path : LocalVideoIndex.normalizeRoot(rootUri);
    const parts = source.split('/').filter((p: string) => p.length > 0);
    if (parts.length === 0) return '根目录';
    return parts[parts.length - 1];
  }

  static groupFolders(items: MediaItem[], rootUri: string): LocalFolderGroup[] {
    const map = new Map<string, LocalFolderGroup>();
    const videos = LocalVideoIndex.pickVideos(items);
    for (let i = 0; i < videos.length; i++) {
      const item = videos[i];
      const path = LocalVideoIndex.folderPath(item, rootUri);
      let group = map.get(path);
      if (!group) {
        group = {
          path: path,
          name: LocalVideoIndex.folderLabel(path, rootUri),
          items: [],
          coverUrl: '',
          totalSize: 0,
          latestAt: 0
        };
        map.set(path, group);
      }
      group.items.push(item);
      group.totalSize += item.fileSize > 0 ? item.fileSize : 0;
      group.latestAt = Math.max(group.latestAt, item.addedAt);
      if (!group.coverUrl && item.posterUrl) group.coverUrl = item.posterUrl;
    }
    const groups: LocalFolderGroup[] = [];
    map.forEach((group: LocalFolderGroup) => {
      groups.push(group);
    });
    groups.sort((a: LocalFolderGroup, b: LocalFolderGroup) => a.name.localeCompare(b.name, 'zh-CN'));
    return groups;
  }

  static filterByType(items: MediaItem[], type: LocalTypeFilter): MediaItem[] {
    if (type === 'all') return items;
    return items.filter((it: MediaItem) => it.mediaType === type);
  }

  /** 画质排序权重：4K > 1080P > 720P > 其他；qualityTag 缺失时看 overview 的分辨率。 */
  static resolutionRank(item: MediaItem): number {
    const text = `${item.qualityTag || ''} ${item.overview || ''}`.toUpperCase();
    if (text.includes('4K') || text.includes('2160')) return 4;
    if (text.includes('1080')) return 3;
    if (text.includes('720')) return 2;
    if (text.includes('480') || text.includes('HD')) return 1;
    return 0;
  }

  static sortVideos(items: MediaItem[], sort: LocalSort): MediaItem[] {
    const out = items.slice();
    out.sort((a: MediaItem, b: MediaItem) => {
      if (sort === 'name') {
        return a.title.localeCompare(b.title, 'zh-CN') || a.fileName.localeCompare(b.fileName, 'zh-CN');
      }
      if (sort === 'size') {
        return (b.fileSize || 0) - (a.fileSize || 0);
      }
      if (sort === 'duration') {
        return (b.durationMs || 0) - (a.durationMs || 0);
      }
      if (sort === 'resolution') {
        const diff = LocalVideoIndex.resolutionRank(b) - LocalVideoIndex.resolutionRank(a);
        return diff !== 0 ? diff : (b.addedAt || 0) - (a.addedAt || 0);
      }
      return (b.addedAt || 0) - (a.addedAt || 0);
    });
    return out;
  }
}

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaSource, RemoteFileEntry } from '../common/Types';
import { RemoteSourceClient } from './RemoteSourceClient';

const LOG_TAG: string = 'PrismLocalArt';

const IMAGE_EXTS: string[] = ['jpg', 'jpeg', 'png', 'webp'];

/**
 * Kodi / Emby 风格的本地海报。
 *
 * 这类影库的封面不是嵌在视频里，而是同目录的图片文件：`影片名-poster.jpg`、`影片名.jpg`、
 * `poster.jpg`、`folder.jpg`。这里负责挑出最合适的一张，经 SMB/WebDAV 取回字节，
 * 落到应用缓存目录，再把本地路径交给 Image 渲染——ArkUI 不能直接渲染 smb:// 资源。
 */
export class LocalArtwork {
  private static hash(value: string): string {
    let h: number = 0;
    for (let i = 0; i < value.length; i++) {
      h = ((h * 31) + value.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(36);
  }

  private static extOf(name: string): string {
    const dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  private static isImage(name: string): boolean {
    return IMAGE_EXTS.indexOf(LocalArtwork.extOf(name)) >= 0;
  }

  /** 该视频应当尝试的图片文件名（小写，按优先级）。 */
  static candidates(videoName: string): string[] {
    const dot = videoName.lastIndexOf('.');
    const base = (dot > 0 ? videoName.substring(0, dot) : videoName).toLowerCase();
    const out: string[] = [];
    for (const ext of IMAGE_EXTS) {
      out.push(`${base}-poster.${ext}`);
    }
    for (const ext of IMAGE_EXTS) {
      out.push(`${base}.${ext}`);
    }
    for (const stem of ['poster', 'folder', 'cover', 'fanart']) {
      for (const ext of IMAGE_EXTS) {
        out.push(`${stem}.${ext}`);
      }
    }
    return out;
  }

  /**
   * 在同目录条目里挑一张封面。
   *
   * @param nfoThumb NFO 里的 `<thumb>`，可能是相对文件名；命中则优先
   */
  static pick(entries: RemoteFileEntry[], videoName: string, nfoThumb?: string): RemoteFileEntry | null {
    const byName: Map<string, RemoteFileEntry> = new Map();
    for (const e of entries) {
      if (e.isDirectory || !LocalArtwork.isImage(e.name)) continue;
      byName.set(e.name.toLowerCase(), e);
    }
    if (byName.size === 0) return null;

    if (nfoThumb) {
      const hit = byName.get(nfoThumb.trim().toLowerCase());
      if (hit) return hit;
    }
    for (const want of LocalArtwork.candidates(videoName)) {
      const hit = byName.get(want);
      if (hit) return hit;
    }
    return null;
  }

  /**
   * 把远端图片落到本地缓存，返回可直接交给 Image 的 `file://` 路径。
   * 失败返回空串——调用方继续用占位图，绝不阻塞扫描。
   */
  static async materialize(context: common.Context, source: MediaSource, entry: RemoteFileEntry): Promise<string> {
    if (!context || !entry) return '';
    const dir = `${context.cacheDir}/artwork`;
    const ext = LocalArtwork.extOf(entry.name) || 'jpg';
    const file = `${dir}/${LocalArtwork.hash(source.id + entry.path)}.${ext}`;

    try {
      if (fs.accessSync(file)) return `file://${file}`;
    } catch (_e) {
      // 尚未缓存
    }

    try {
      const bytes: ArrayBuffer = await RemoteSourceClient.fetchImageBytes(entry.fullUrl, source);
      if (!bytes || bytes.byteLength === 0) return '';

      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const fh = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(fh.fd, bytes);
      } finally {
        fs.closeSync(fh);
      }
      hilog.info(0x0001, LOG_TAG, 'artwork cached: %{public}s (%{public}d B)', entry.name, bytes.byteLength);
      return `file://${file}`;
    } catch (err) {
      hilog.warn(0x0001, LOG_TAG, 'artwork fetch failed: %{public}s', JSON.stringify(err));
      return '';
    }
  }
}

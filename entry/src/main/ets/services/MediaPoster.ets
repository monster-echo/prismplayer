import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaItem } from '../common/Types';

const LOG_TAG: string = 'PrismPoster';

/**
 * 本机媒体的封面：视频抽首帧，音频读内嵌专辑图。
 * 产物只落在 filesDir/posters（几十 KB），媒体文件本身不动。
 */
export class MediaPoster {
  private static hash(value: string): string {
    let h: number = 0;
    for (let i = 0; i < value.length; i++) {
      h = ((h * 31) + value.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(36);
  }

  private static cacheDir(context: common.Context): string {
    return `${context.filesDir}/posters`;
  }

  static async ensure(context: common.Context, item: MediaItem): Promise<string> {
    if (!context || item.sourceType !== 'local') return '';
    if (item.posterUrl) return item.posterUrl;

    const dir = MediaPoster.cacheDir(context);
    const dest = `${dir}/${MediaPoster.hash(item.id)}.jpg`;
    try {
      if (fs.accessSync(dest)) return `file://${dest}`;
    } catch (_e) {
      // 尚未生成
    }

    const isAudio = item.mediaType === 'track';
    let fd: number = -1;
    let pixel: image.PixelMap | null = null;
    try {
      const file = fs.openSync(item.streamUrl, fs.OpenMode.READ_ONLY);
      fd = file.fd;
      const size = fs.statSync(fd).size;

      if (isAudio) {
        const extractor = await media.createAVMetadataExtractor();
        try {
          extractor.fdSrc = { fd, offset: 0, length: size };
          pixel = await extractor.fetchAlbumCover();
        } finally {
          await extractor.release();
        }
      } else {
        const generator = await media.createAVImageGenerator();
        try {
          generator.fdSrc = { fd, offset: 0, length: size };
          pixel = await generator.fetchFrameByTime(
            1000000,
            media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
            { width: 480, height: 270 }
          );
        } finally {
          await generator.release();
        }
      }
      if (!pixel) return '';

      const packer = image.createImagePacker();
      let data: ArrayBuffer;
      try {
        data = await packer.packing(pixel, { format: 'image/jpeg', quality: 80 });
      } finally {
        packer.release();
      }
      if (!data || data.byteLength === 0) return '';

      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const out = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(out.fd, data);
      } finally {
        fs.closeSync(out);
      }
      hilog.info(0x0001, LOG_TAG, 'artwork ready id=%{public}s bytes=%{public}d', item.id, data.byteLength);
      return `file://${dest}`;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'artwork skipped id=%{public}s err=%{public}s', item.id,
        e instanceof Error ? e.message : JSON.stringify(e));
      return '';
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (_e) {
          // Ignore
        }
      }
      if (pixel) {
        try {
          await pixel.release();
        } catch (_e) {
          // Ignore
        }
      }
    }
  }
}

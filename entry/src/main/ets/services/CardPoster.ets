import { common } from '@kit.AbilityKit';
import { MediaArtwork } from '../common/MediaArtwork';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_TAG: string = 'PrismCardPoster';

/**
 * 卡片专用的海报落地。
 *
 * 卡片进程读不到网络图，也无法跨进程共享内存，所以必须由主进程先把海报落成本地文件，
 * 再由 FormAbility 打开文件句柄、通过 formImages 交给卡片渲染。
 *
 * 只在「继续观看」那一条上做，失败了就让卡片退化成纯文字，绝不阻塞播放链路。
 */
export class CardPoster {
  static isUsable(posterUrl: string): boolean {
    return posterUrl.startsWith('http://') || posterUrl.startsWith('https://') || posterUrl.startsWith('local://');
  }

  private static hash(value: string): string {
    let h: number = 0;
    for (let i = 0; i < value.length; i++) {
      h = ((h * 31) + value.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(36);
  }

  /** 返回本机绝对路径；拿不到就返回空串。 */
  static async ensure(context: common.Context, posterUrl: string): Promise<string> {
    if (!CardPoster.isUsable(posterUrl)) return '';
    const path: string = `${context.cacheDir}/card_poster_${CardPoster.hash(posterUrl)}.img`;
    try {
      if (fs.accessSync(path)) return path;
    } catch (_e) {
      // Not cached yet
    }
    // 内置演示片源走 local:// 协议，直接读安装包里的海报资源
    if (posterUrl.startsWith('local://')) {
      try {
        const art: ResourceStr = MediaArtwork.resolve(posterUrl);
        if (typeof art === 'string') return '';
        const bytes: Uint8Array = context.resourceManager.getMediaContentSync(art.id);
        hilog.info(0x0001, LOG_TAG, 'local poster bytes=%{public}d', bytes.byteLength);
        const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
        fs.closeSync(file);
        hilog.info(0x0001, LOG_TAG, 'local poster written %{public}s', path);
        return path;
      } catch (e) {
        hilog.warn(0x0001, LOG_TAG, 'local poster failed: %{public}s', JSON.stringify(e));
        return '';
      }
    }
    try {
      const req = http.createHttp();
      const resp = await req.request(posterUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 4000,
        readTimeout: 6000
      });
      req.destroy();
      if (resp.responseCode !== 200 || !(resp.result instanceof ArrayBuffer)) {
        hilog.warn(0x0001, LOG_TAG, 'poster http %{public}d', resp.responseCode);
        return '';
      }
      const bytes = resp.result as ArrayBuffer;
      if (bytes.byteLength === 0 || bytes.byteLength > 6 * 1024 * 1024) return '';
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes);
      fs.closeSync(file);
      return path;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'poster download failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }
}

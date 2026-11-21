import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { deferredLink } from '@kit.AppLinkingKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaItem } from '../common/Types';
import { AppConstants } from '../common/Constants';

const LOG_TAG: string = 'PrismShare';
/** 分享卡片只露一两行，过长的片名和简介塞不下，还会把 Want 数据撑大。 */
const TITLE_LIMIT: number = 60;
const DESC_LIMIT: number = 100;
/** 卡片缩略图只有小方块大小，480 宽足够，再大只是把 Want 数据往 IPC 上限上怼。 */
const THUMBNAIL_WIDTH: number = 480;

export interface AppLinkTarget {
  itemId: string;
  positionMs: number;
}

/**
 * 分享回流。
 *
 * 分享出去的是一条 App Linking 链接：已安装直接进播放页，未安装先落商店、装完由
 * deferredLink 把这条链接交还给我们，落地即起播。
 */
export class ShareService {
  static buildShareUrl(item: MediaItem, positionMs: number): string {
    const base: string = AppConstants.APP_LINK_BASE;
    const sep: string = base.indexOf('?') >= 0 ? '&' : '?';
    return `${base}${sep}item=${encodeURIComponent(item.id)}&pos=${Math.round(positionMs)}`;
  }

  static async shareMediaItem(
    context: common.UIAbilityContext,
    item: MediaItem,
    positionMs: number,
    thumbnailUri?: string
  ): Promise<boolean> {
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        // 链接必须走 content：uri 只接文件 URI，塞 https 链接会被判成无效记录，
        // 分享面板于是根本拉不起来（点「分享这部片」像是什么都没发生）。
        content: ShareService.buildShareUrl(item, positionMs),
        title: ShareService.clip(item.title || 'PrismPlayer', TITLE_LIMIT),
        description: ShareService.clip(item.overview || '在 PrismPlayer 中打开这部片', DESC_LIMIT)
      };
      // 缩略图走 URI：图片字节直接塞进 record 会撞上 Want 的 IPC 上限
      if (thumbnailUri) record.thumbnailUri = thumbnailUri;
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE });
      return true;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'share failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 把画面帧压成分享卡缩略图，落一张图到 cache 并返回其 file URI。
   *
   * 传入的 PixelMap 由本方法负责释放；失败返回空串，分享照常继续（只是没有缩略图）。
   */
  static async saveFrameThumbnail(context: common.UIAbilityContext, frame: image.PixelMap): Promise<string> {
    let packer: image.ImagePacker | null = null;
    try {
      const info: image.ImageInfo = await frame.getImageInfo();
      const width: number = info.size.width;
      if (width > THUMBNAIL_WIDTH) {
        const ratio: number = THUMBNAIL_WIDTH / width;
        await frame.scale(ratio, ratio);
      }
      packer = image.createImagePacker();
      const option: image.PackingOption = { format: 'image/jpeg', quality: 55 };
      const bytes: ArrayBuffer = await packer.packToData(frame, option);
      const path: string = `${context.cacheDir}/prism-share-frame.jpg`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes);
      fs.closeSync(file);
      return fileUri.getUriFromPath(path);
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'frame thumbnail failed: %{public}s', JSON.stringify(e));
      return '';
    } finally {
      if (packer) {
        packer.release().catch(() => {});
      }
      frame.release().catch(() => {});
    }
  }

  /** 系统分享面板拉不起来时的退路：链接进剪贴板，用户还能粘贴出去。 */
  static copyShareUrl(item: MediaItem, positionMs: number): boolean {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, ShareService.buildShareUrl(item, positionMs));
      pasteboard.getSystemPasteboard().setDataSync(data);
      return true;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'copy share url failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  private static clip(text: string, limit: number): string {
    const trimmed: string = text.trim();
    return trimmed.length > limit ? `${trimmed.substring(0, limit)}…` : trimmed;
  }

  /** 首次安装启动时取回「点了链接才来」的那次分享目标；没有则返回 null。 */
  static async popPendingLink(): Promise<AppLinkTarget | null> {
    try {
      const raw: string = await deferredLink.popDeferredLink();
      return ShareService.parseLink(raw);
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'popDeferredLink failed: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  /** want.uri / deferredLink 统一解析，入参可以是完整 URL。 */
  static parseLink(raw?: string): AppLinkTarget | null {
    if (!raw) return null;
    const queryIndex: number = raw.indexOf('?');
    if (queryIndex < 0) return null;
    const query: string = raw.substring(queryIndex + 1);
    let itemId: string = '';
    let positionMs: number = 0;
    const pairs: string[] = query.split('&');
    for (let i = 0; i < pairs.length; i++) {
      const pair: string = pairs[i];
      const eq: number = pair.indexOf('=');
      if (eq <= 0) continue;
      const key: string = pair.substring(0, eq);
      const value: string = decodeURIComponent(pair.substring(eq + 1));
      if (key === 'item') itemId = value;
      else if (key === 'pos') {
        const parsed: number = Number(value);
        positionMs = Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
      }
    }
    if (!itemId) return null;
    return { itemId, positionMs };
  }
}

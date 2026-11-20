import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { deferredLink } from '@kit.AppLinkingKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaItem } from '../common/Types';
import { AppConstants } from '../common/Constants';

const LOG_TAG: string = 'PrismShare';

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
    positionMs: number
  ): Promise<boolean> {
    try {
      const url: string = ShareService.buildShareUrl(item, positionMs);
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        uri: url,
        title: item.title || 'PrismPlayer',
        description: item.overview ? item.overview : '在 PrismPlayer 中打开这部片'
      };
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE });
      return true;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'share failed: %{public}s', JSON.stringify(e));
      return false;
    }
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

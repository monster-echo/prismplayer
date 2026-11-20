import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';
import { ProTier } from '../common/Types';

export interface IapProductDisplay {
  productId: string;
  tier: ProTier;
  title: string;
  priceText: string;
  /** 有活动价时的原价，空串表示无活动 */
  originalPriceText: string;
  badge: string;
  description: string;
}

export interface IapActionResult {
  success: boolean;
  tier: ProTier;
  message: string;
}

/** 华为 IAP 订单载荷中我们关心的字段（其余字段不参与判断）。 */
interface IapPurchasePayload {
  productId?: string;
  purchaseToken?: string;
  purchaseOrderId?: string;
  purchaseState?: number;
  purchaseType?: number;
  consumptionState?: number;
}

const TAG = 'PrismIap';

export const DEFAULT_IAP_PRODUCTS: IapProductDisplay[] = [
  {
    productId: AppConstants.IAP_PRO_STANDARD,
    tier: 'pro_lifetime',
    title: '个人永久版',
    priceText: '¥48',
    originalPriceText: '',
    badge: '主推方案',
    description: '一次买断，永久解锁全部功能：无限片源、4K HDR、ASS 字幕，三端通用'
  },
  {
    productId: AppConstants.IAP_PRO_FAMILY,
    tier: 'pro_family',
    title: '家庭永久版',
    priceText: '¥68',
    originalPriceText: '',
    badge: '家庭共享',
    description: '一次买断，永久解锁全部功能，可通过华为家庭组与最多 5 位家人共享'
  }
];

export class IapService {
  /** 查 AGC 上配置的商品；查不到（未配置/未联网）时回落到本地展示价。 */
  static async queryProducts(context: common.UIAbilityContext): Promise<IapProductDisplay[]> {
    try {
      const param: iap.QueryProductsParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [
          AppConstants.IAP_PRO_STANDARD,
          AppConstants.IAP_PRO_FAMILY
        ]
      };
      const products = await iap.queryProducts(context, param);
      if (!products || products.length === 0) {
        return DEFAULT_IAP_PRODUCTS;
      }
      return DEFAULT_IAP_PRODUCTS.map((defItem) => {
        const matched = products.find(p => p.id === defItem.productId);
        if (!matched) return defItem;
        const hasPromo = matched.originalMicroPrice > 0 && matched.microPrice > 0
          && matched.originalMicroPrice > matched.microPrice;
        return {
          productId: defItem.productId,
          tier: defItem.tier,
          title: matched.name || defItem.title,
          priceText: matched.localPrice || defItem.priceText,
          originalPriceText: hasPromo && matched.originalLocalPrice ? matched.originalLocalPrice : '',
          badge: defItem.badge,
          description: matched.description || defItem.description
        };
      });
    } catch (e) {
      hilog.warn(0x0001, TAG, 'queryProducts failed: %{public}s', IapService.errText(e));
      return DEFAULT_IAP_PRODUCTS;
    }
  }

  /**
   * 拉起华为收银台。只有拿到 purchaseState=0 的订单才算成功，
   * 成功后再 finishPurchase 确认发货；取消/失败一律不授予 Pro。
   */
  static async purchase(context: common.UIAbilityContext, product: IapProductDisplay): Promise<IapActionResult> {
    try {
      const param: iap.PurchaseParameter = {
        productId: product.productId,
        productType: iap.ProductType.NONCONSUMABLE
      };
      const result = await iap.createPurchase(context, param);
      const payload = IapService.parsePayload(result.purchaseData);
      if (!payload) {
        hilog.error(0x0001, TAG, 'purchase: empty payload product=%{public}s', product.productId);
        return { success: false, tier: 'free', message: '支付结果为空，请稍后在「恢复购买」中重试' };
      }
      if (payload.purchaseState !== 0) {
        hilog.warn(0x0001, TAG, 'purchase: state=%{public}d product=%{public}s',
          payload.purchaseState ?? -1, product.productId);
        return { success: false, tier: 'free', message: '支付未完成或已取消' };
      }
      await IapService.finish(context, payload);
      hilog.info(0x0001, TAG, 'purchase ok product=%{public}s order=%{public}s',
        payload.productId || product.productId, payload.purchaseOrderId || '');
      return {
        success: true,
        tier: IapService.tierOf(payload.productId || product.productId, product.tier),
        message: `已成功解锁「${product.title}」`
      };
    } catch (e) {
      const msg = IapService.errText(e);
      hilog.error(0x0001, TAG, 'purchase failed product=%{public}s err=%{public}s', product.productId, msg);
      return {
        success: false,
        tier: 'free',
        message: `支付未完成：${msg}（需 AppGallery 正式签名包与已上架商品）`
      };
    }
  }

  /** 用当前华为账号恢复历史买断权益（换机/重装后调用）。 */
  static async restorePurchases(context: common.UIAbilityContext): Promise<IapActionResult> {
    try {
      const param: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.NONCONSUMABLE
      };
      const res = await iap.queryOwnedPurchases(context, param);
      const list: string[] = res.inAppPurchaseDataList || [];
      if (list.length === 0) {
        return { success: false, tier: 'free', message: '当前华为账号暂未查询到历史买断订单' };
      }
      let best: ProTier = 'free';
      let bestProduct = '';
      for (const raw of list) {
        const payload = IapService.parsePayload(raw);
        if (!payload || payload.purchaseState !== 0) continue;
        const tier = IapService.tierOf(payload.productId || '', 'free');
        if (IapService.rank(tier) > IapService.rank(best)) {
          best = tier;
          bestProduct = payload.productId || '';
        }
      }
      if (best === 'free') {
        return { success: false, tier: 'free', message: '订单存在但未完成发货，请在「恢复购买」中重试' };
      }
      hilog.info(0x0001, TAG, 'restore ok product=%{public}s tier=%{public}s', bestProduct, best);
      return { success: true, tier: best, message: '已从华为账号恢复买断权益' };
    } catch (e) {
      const msg = IapService.errText(e);
      hilog.warn(0x0001, TAG, 'restore failed: %{public}s', msg);
      return { success: false, tier: 'free', message: `恢复购买不可用：${msg}` };
    }
  }

  private static parsePayload(raw: string): IapPurchasePayload | null {
    if (!raw) return null;
    try {
      return JSON.parse(raw) as IapPurchasePayload;
    } catch (_e) {
      return null;
    }
  }

  private static async finish(context: common.UIAbilityContext, payload: IapPurchasePayload): Promise<void> {
    if (!payload.purchaseToken || !payload.purchaseOrderId) {
      hilog.warn(0x0001, TAG, 'finish skipped: token/order missing');
      return;
    }
    try {
      await iap.finishPurchase(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        purchaseToken: payload.purchaseToken,
        purchaseOrderId: payload.purchaseOrderId
      });
    } catch (e) {
      // 确认失败不回滚权益：订单仍是 UNFINISHED，下次恢复购买会重新确认。
      hilog.warn(0x0001, TAG, 'finishPurchase failed: %{public}s', IapService.errText(e));
    }
  }

  private static tierOf(productId: string, fallback: ProTier): ProTier {
    const matched = DEFAULT_IAP_PRODUCTS.find(p => p.productId === productId);
    return matched ? matched.tier : fallback;
  }

  private static rank(tier: ProTier): number {
    if (tier === 'pro_family') return 3;
    if (tier === 'pro_lifetime') return 2;
    if (tier === 'pro_early') return 1;
    return 0;
  }

  private static errText(e: Object): string {
    if (e instanceof Error) return e.message;
    return String(e);
  }
}

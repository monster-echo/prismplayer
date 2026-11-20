import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
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

/**
 * createPurchase 返回的 purchaseData（新 API）：
 * 顶层只有 jwsPurchaseOrder 等 JWS 字段，订单明细在其 payload 中。
 */
interface PurchaseDataEnvelope {
  jwsPurchaseOrder?: string;
}

/** jwsPurchaseOrder 解码后的订单载荷（PurchaseOrderPayload）。 */
interface PurchaseOrderPayload {
  productType?: number;
  purchaseToken?: string;
  purchaseOrderId?: string;
  finishStatus?: number;
  /** 撤回原因码；为空代表购买成功。 */
  purchaseOrderRevocationReasonCode?: string;
  productId?: string;
}

/** queryOwnedPurchases 返回的订单载荷（旧 InAppPurchaseData 结构）。 */
interface IapPurchasePayload {
  productId?: string;
  purchaseToken?: string;
  orderId?: string;
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
   * 拉起华为收银台（新 API）。购买结果在 purchaseData.jwsPurchaseOrder 的 JWS 载荷里，
   * purchaseOrderRevocationReasonCode 为空即支付成功；成功后先发权益再 finishPurchase 确认。
   */
  static async purchase(context: common.UIAbilityContext, product: IapProductDisplay): Promise<IapActionResult> {
    try {
      const param: iap.PurchaseParameter = {
        productId: product.productId,
        productType: iap.ProductType.NONCONSUMABLE
      };
      const result = await iap.createPurchase(context, param);
      hilog.info(0x0001, TAG, 'purchase raw product=%{public}s data=%{public}s',
        product.productId, result.purchaseData || '');
      const envelope = IapService.parsePayload(result.purchaseData) as PurchaseDataEnvelope | null;
      const payload = envelope?.jwsPurchaseOrder
        ? IapService.decodeJwsPayload(envelope.jwsPurchaseOrder)
        : null;
      if (!payload || !payload.purchaseToken || !payload.purchaseOrderId) {
        hilog.error(0x0001, TAG, 'purchase: empty/unparsable payload product=%{public}s', product.productId);
        return { success: false, tier: 'free', message: '支付结果解析失败，请稍后在「恢复购买」中重试' };
      }
      if (payload.purchaseOrderRevocationReasonCode) {
        hilog.warn(0x0001, TAG, 'purchase revoked product=%{public}s reason=%{public}s',
          product.productId, payload.purchaseOrderRevocationReasonCode);
        return { success: false, tier: 'free', message: '支付未完成或已撤销' };
      }
      await IapService.finishOrder(context, payload.purchaseToken, payload.purchaseOrderId);
      hilog.info(0x0001, TAG, 'purchase ok product=%{public}s order=%{public}s',
        payload.productId || product.productId, payload.purchaseOrderId);
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
        message: `支付未完成：${msg}（如有未完成订单，请点「恢复购买」后重试）`
      };
    }
  }

  /** 用当前华为账号恢复历史买断权益（换机/重装后调用），并补确认未 finish 的订单。 */
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
        const payload = IapService.parsePayload(raw) as IapPurchasePayload | null;
        if (!payload || payload.purchaseState !== 0) continue;
        const tier = IapService.tierOf(payload.productId || '', 'free');
        if (IapService.rank(tier) > IapService.rank(best)) {
          best = tier;
          bestProduct = payload.productId || '';
        }
        // 恢复权益视为发货，顺手把可能未确认的订单补 finish（旧结构订单号字段为 orderId）。
        if (payload.purchaseToken && payload.orderId) {
          await IapService.finishOrder(context, payload.purchaseToken, payload.orderId);
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

  /** 兼容旧/新两种 JSON 载荷的解析（内容结构由调用方收窄）。 */
  private static parsePayload(raw: string): object | null {
    if (!raw) return null;
    try {
      return JSON.parse(raw) as object;
    } catch (_e) {
      return null;
    }
  }

  /** 解 JWS（header.payload.signature）的 payload 段，不校验签名（纯客户端应用，无服务端验签条件）。 */
  private static decodeJwsPayload(jws: string): PurchaseOrderPayload | null {
    try {
      const parts = jws.split('.');
      if (parts.length < 2) return null;
      let b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const pad = b64.length % 4;
      if (pad === 2) b64 += '==';
      else if (pad === 3) b64 += '=';
      const bytes = new util.Base64Helper().decodeSync(b64);
      const text = util.TextDecoder.create('utf-8').decodeToString(bytes);
      return JSON.parse(text) as PurchaseOrderPayload;
    } catch (_e) {
      return null;
    }
  }

  private static async finishOrder(context: common.UIAbilityContext, purchaseToken: string,
    purchaseOrderId: string): Promise<void> {
    try {
      await iap.finishPurchase(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        purchaseToken: purchaseToken,
        purchaseOrderId: purchaseOrderId
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
    const bizErr = e as BusinessError;
    if (bizErr && bizErr.code !== undefined) {
      return `${bizErr.code}: ${bizErr.message ?? ''}`;
    }
    return JSON.stringify(e);
  }
}

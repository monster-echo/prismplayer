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

/** 商品目录。fromStore=false 时价格只是本地占位，不能当真实售价展示。 */
export interface IapCatalog {
  items: IapProductDisplay[];
  fromStore: boolean;
}

/** 接口返回的原始订单数据：新 API 只有 jwsPurchaseOrder，旧 API 是扁平 JSON。 */
interface RawOrderData {
  jwsPurchaseOrder?: string;
  productId?: string;
  purchaseToken?: string;
  orderId?: string;
  purchaseState?: number;
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

/** 新旧两种载荷统一后的订单视图。 */
interface OrderView {
  productId: string;
  purchaseToken: string;
  orderId: string;
  /** false 代表已撤销/退款或未支付。 */
  paid: boolean;
}

const TAG = 'PrismIap';

const UNSUPPORTED_MSG = '当前设备不支持应用内购买';

/** queryPurchases 分页上限：个人账号买断订单远小于 5×100 条。 */
const MAX_QUERY_PAGES = 5;

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
  /**
   * 当前设备是否具备应用内支付能力。
   * 模拟器或缺少华为服务的设备上 IAPKit 模块不会加载，`iap` 为 undefined，
   * 直接访问 `iap.ProductType` 会抛 TypeError（表现为「Cannot read property ProductType of undefined」），
   * 所以任何调支付接口前都先走这里。
   */
  static isSupported(): boolean {
    try {
      return canIUse('SystemCapability.Payment.IAP')
        && iap.ProductType.NONCONSUMABLE !== undefined;
    } catch (_e) {
      return false;
    }
  }

  /** 查应用市场上的商品；查不到或设备不支持时 fromStore=false，只回本地占位价。 */
  static async queryProducts(context: common.UIAbilityContext): Promise<IapCatalog> {
    if (!IapService.isSupported()) {
      hilog.info(0x0001, TAG, 'queryProducts skipped: IAP unsupported on this device');
      return { items: DEFAULT_IAP_PRODUCTS, fromStore: false };
    }
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
        hilog.warn(0x0001, TAG, 'queryProducts returned empty list');
        return { items: DEFAULT_IAP_PRODUCTS, fromStore: false };
      }
      const items = DEFAULT_IAP_PRODUCTS.map((defItem) => {
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
      // 任一商品没查到，其价格仍是本地占位值，整体按“未同步”处理，避免展示假价格。
      const fromStore = DEFAULT_IAP_PRODUCTS.every(
        (defItem) => products.some((p) => p.id === defItem.productId));
      return { items: items, fromStore: fromStore };
    } catch (e) {
      hilog.warn(0x0001, TAG, 'queryProducts failed: %{public}s', IapService.errText(e));
      return { items: DEFAULT_IAP_PRODUCTS, fromStore: false };
    }
  }

  /**
   * 拉起华为收银台。购买结果在 purchaseData.jwsPurchaseOrder 的 JWS 载荷里，
   * purchaseOrderRevocationReasonCode 为空即支付成功；成功后先发权益再 finishPurchase 确认。
   */
  static async purchase(context: common.UIAbilityContext, product: IapProductDisplay): Promise<IapActionResult> {
    if (!IapService.isSupported()) {
      return { success: false, tier: 'free', message: UNSUPPORTED_MSG };
    }
    try {
      const param: iap.PurchaseParameter = {
        productId: product.productId,
        productType: iap.ProductType.NONCONSUMABLE
      };
      const result = await iap.createPurchase(context, param);
      hilog.info(0x0001, TAG, 'purchase raw product=%{public}s data=%{public}s',
        product.productId, result.purchaseData || '');
      const payload = IapService.decodeJwsOrder(result.purchaseData);
      if (!payload || !payload.purchaseToken || !payload.purchaseOrderId) {
        hilog.error(0x0001, TAG, 'purchase: empty/unparsable payload product=%{public}s', product.productId);
        return { success: false, tier: 'free', message: '支付结果解析失败，请点右上角「恢复购买」重试' };
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
        message: `已解锁「${product.title}」`
      };
    } catch (e) {
      hilog.error(0x0001, TAG, 'purchase failed product=%{public}s err=%{public}s',
        product.productId, IapService.errText(e));
      return { success: false, tier: 'free', message: `支付未完成：${IapService.friendlyError(e)}` };
    }
  }

  /**
   * 用当前华为账号恢复历史买断权益（换机/重装后调用），并补确认未 finish 的订单。
   * queryOwnedPurchases 自 4.1.0(11) 废弃，改用 queryPurchases(queryType: ALL)。
   */
  static async restorePurchases(context: common.UIAbilityContext): Promise<IapActionResult> {
    if (!IapService.isSupported()) {
      return { success: false, tier: 'free', message: UNSUPPORTED_MSG };
    }
    try {
      let best: ProTier = 'free';
      let bestProduct = '';
      /** 账号下确实有已支付的买断订单，但都没能换算成权益（发货未完成）。 */
      let sawPaidOrder = false;
      let token: string | undefined = undefined;
      for (let page = 1; page <= MAX_QUERY_PAGES; page++) {
        const param: iap.QueryPurchasesParameter = {
          productType: iap.ProductType.NONCONSUMABLE,
          queryType: iap.PurchaseQueryType.ALL
        };
        if (token) {
          param.continuationToken = token;
        }
        const res = await iap.queryPurchases(context, param);
        const list: string[] = res.purchaseDataList || [];
        for (const raw of list) {
          const order = IapService.parseOrder(raw);
          if (!order || !order.paid) continue;
          sawPaidOrder = true;
          // 恢复权益视为发货，顺手把可能未确认的订单补 finish。
          if (order.purchaseToken && order.orderId) {
            await IapService.finishOrder(context, order.purchaseToken, order.orderId);
          }
          const tier = IapService.tierOf(order.productId, 'free');
          if (IapService.rank(tier) > IapService.rank(best)) {
            best = tier;
            bestProduct = order.productId;
          }
        }
        token = res.continuationToken;
        if (!token) break;
      }
      if (best === 'free') {
        return {
          success: false,
          tier: 'free',
          message: sawPaidOrder ? '订单未完成发货，请稍后重试' : '当前华为账号无买断记录'
        };
      }
      hilog.info(0x0001, TAG, 'restore ok product=%{public}s tier=%{public}s', bestProduct, best);
      return { success: true, tier: best, message: '已恢复买断权益' };
    } catch (e) {
      hilog.warn(0x0001, TAG, 'restore failed: %{public}s', IapService.errText(e));
      return { success: false, tier: 'free', message: IapService.friendlyError(e) };
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

  /** 从 createPurchase 的 purchaseData 里取出 JWS 订单载荷。 */
  private static decodeJwsOrder(purchaseData: string): PurchaseOrderPayload | null {
    const envelope = IapService.parsePayload(purchaseData) as RawOrderData | null;
    return envelope?.jwsPurchaseOrder ? IapService.decodeJwsPayload(envelope.jwsPurchaseOrder) : null;
  }

  /** 把查询到的订单归一到 OrderView：新格式解 JWS，旧格式读扁平字段。 */
  private static parseOrder(raw: string): OrderView | null {
    const data = IapService.parsePayload(raw) as RawOrderData | null;
    if (!data) return null;
    if (data.jwsPurchaseOrder) {
      const payload = IapService.decodeJwsPayload(data.jwsPurchaseOrder);
      if (!payload) return null;
      return {
        productId: payload.productId || '',
        purchaseToken: payload.purchaseToken || '',
        orderId: payload.purchaseOrderId || '',
        paid: !payload.purchaseOrderRevocationReasonCode
      };
    }
    return {
      productId: data.productId || '',
      purchaseToken: data.purchaseToken || '',
      orderId: data.orderId || '',
      paid: data.purchaseState === 0
    };
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

  /** 把失败收敛成一句可操作的话：不把裸 JS 异常扔给用户（错误码含义取自 IAPKit 的 @throws 声明）。 */
  private static friendlyError(e: Object): string {
    const code: number | undefined = (e as BusinessError)?.code;
    switch (code) {
      case 801: return UNSUPPORTED_MSG;
      case 1001860000: return '已取消支付';
      case 1001860002: return '应用未授权，请通过华为应用市场安装后重试';
      case 1001860003: return '商品信息无效，请稍后重试';
      case 1001860004: return '操作过于频繁，请稍后重试';
      case 1001860005: return '网络异常，请检查网络后重试';
      case 1001860007: return '当前地区暂未上架该商品';
      case 1001860050: return '请先登录华为账号';
      case 1001860054: return '当前账号所在国家或地区不支持应用内购买';
      default: break;
    }
    if (code !== undefined) {
      return `内购服务暂不可用（${code}）`;
    }
    return '内购服务不可用，请更新系统后重试';
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

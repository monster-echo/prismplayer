import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../common/Constants';
import { ProTier } from '../common/Types';

export interface IapProductDisplay {
  productId: string;
  tier: ProTier;
  title: string;
  priceText: string;
  badge: string;
  description: string;
}

export interface IapActionResult {
  success: boolean;
  tier: ProTier;
  message: string;
}

export const DEFAULT_IAP_PRODUCTS: IapProductDisplay[] = [
  {
    productId: AppConstants.IAP_PRO_EARLY,
    tier: 'pro_early',
    title: '早鸟买断 Pro',
    priceText: '¥38',
    badge: '限时特惠',
    description: '无限 WebDAV/SMB 片源 · 4K HDR/HEVC · ASS 特效字幕 · TMDB 海报墙'
  },
  {
    productId: AppConstants.IAP_PRO_STANDARD,
    tier: 'pro_lifetime',
    title: '标准永久买断版',
    priceText: '¥48',
    badge: '主推方案',
    description: '同华为账号下 纯血手机 + 平板 + 鸿蒙电脑三端全功能永久解锁'
  },
  {
    productId: AppConstants.IAP_PRO_FAMILY,
    tier: 'pro_family',
    title: '家庭跨端尊享版',
    priceText: '¥68',
    badge: '家庭共享',
    description: '支持华为家庭组共享（最多 5 人）· 全端媒体库同步与优先更新'
  }
];

export class IapService {
  static async queryProducts(context: common.UIAbilityContext): Promise<IapProductDisplay[]> {
    try {
      const param: iap.QueryProductsParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [
          AppConstants.IAP_PRO_EARLY,
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
        return {
          productId: defItem.productId,
          tier: defItem.tier,
          title: matched.name || defItem.title,
          priceText: matched.localPrice || defItem.priceText,
          badge: defItem.badge,
          description: matched.description || defItem.description
        };
      });
    } catch (_e) {
      return DEFAULT_IAP_PRODUCTS;
    }
  }

  static async purchase(context: common.UIAbilityContext, product: IapProductDisplay): Promise<IapActionResult> {
    try {
      const param: iap.PurchaseParameter = {
        productId: product.productId,
        productType: iap.ProductType.NONCONSUMABLE
      };
      await iap.createPurchase(context, param);
      return {
        success: true,
        tier: product.tier,
        message: `已成功解锁「${product.title}」`
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return {
        success: false,
        tier: 'free',
        message: `IAP 支付未完成（需已签名的华为应用市场联运环境）: ${msg}`
      };
    }
  }

  static async restorePurchases(context: common.UIAbilityContext): Promise<IapActionResult> {
    try {
      const param: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        queryType: iap.PurchaseQueryType.ALL
      };
      const res = await iap.queryPurchases(context, param);
      const dataList = res.purchaseDataList || [];
      if (dataList.length > 0) {
        const joined = dataList.join(',');
        let tier: ProTier = 'pro_lifetime';
        if (joined.includes(AppConstants.IAP_PRO_FAMILY)) tier = 'pro_family';
        else if (joined.includes(AppConstants.IAP_PRO_EARLY)) tier = 'pro_early';
        return {
          success: true,
          tier,
          message: '已从华为账号恢复历史买断权益'
        };
      }
      return {
        success: false,
        tier: 'free',
        message: '当前华为账号暂未查询到历史买断订单'
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return {
        success: false,
        tier: 'free',
        message: `恢复购买不可用: ${msg}`
      };
    }
  }
}

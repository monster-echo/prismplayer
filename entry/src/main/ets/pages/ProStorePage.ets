import { common } from '@kit.AbilityKit';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PageShell } from '../components/PageShell';
import { AppStore } from '../services/AppStore';
import { DEFAULT_IAP_PRODUCTS, IapProductDisplay, IapService } from '../services/IapService';

@Entry
@ComponentV2
struct ProStorePage {
  @Local store: AppStore = AppStore.getInstance();
  @Local products: IapProductDisplay[] = DEFAULT_IAP_PRODUCTS;
  @Local selectedIndex: number = 0;
  @Local busy: boolean = false;
  @Local statusMsg: string = '';
  /** 价格是否真的来自应用市场；未同步时页面不展示任何售价。 */
  @Local priceKnown: boolean = false;
  @Local iapSupported: boolean = IapService.isSupported();

  aboutToAppear(): void {
    if (!this.iapSupported) return;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    IapService.queryProducts(ctx).then((catalog) => {
      this.products = catalog.items;
      this.priceKnown = catalog.fromStore;
    });
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private buyLabel(): string {
    if (this.busy) return '正在拉起华为支付...';
    if (this.store.isPro) return '已激活永久买断权益';
    if (!this.iapSupported) return '当前设备不支持内购';
    const price = this.priceKnown ? this.products[this.selectedIndex]?.priceText : '';
    return price ? `立即买断解锁 ${price}` : '立即买断解锁';
  }

  @Builder
  benefitCard(icon: Resource, title: string, desc: string) {
    Row({ space: 12 }) {
      Column() {
        Image(icon).width(24).height(24)
      }
      .width(42)
      .height(42)
      .borderRadius(11)
      .backgroundColor($r('app.color.fill_subtle'))
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(desc)
          .fontSize(11)
          .lineHeight(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.bg_elevated'))
    .border({ width: 0.7, color: $r('app.color.border_subtle') })
  }

  build() {
    Column() {
      NavHeaderBar({
        title: 'PrismPlayer Pro 会员',
        subtitle: '一次买断 · 手机 / 平板 / 鸿蒙电脑三端通用',
        rightLabel: this.iapSupported ? '恢复购买' : '',
        onBack: () => this.getUIContext().getRouter().back(),
        onRightAction: async () => {
          this.busy = true;
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          const res = await IapService.restorePurchases(ctx);
          this.busy = false;
          this.statusMsg = res.message;
          if (res.success) {
            await this.store.applyProTier(res.tier);
          }
        }
      })

      Stack() {
        PageShell({ maxWidth: 1000 }) {
          Column() {

            Scroll() {
              Column({ space: 18 }) {
                // Crown Crest Hero Card
                Column({ space: 10 }) {
                  Row({ space: 12 }) {
                    Image($r('app.media.ic_pro_crown')).width(44).height(44)
                    Column({ space: 3 }) {
                      Text(this.store.isPro ? 'PrismPlayer Pro 已永久激活' : '解锁专业私有云播放完整体验')
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.accent_gold'))
                      Text('拒绝按年订阅 · 纯血 HarmonyOS 账号权益全端同步')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }.width('100%')
                }
                .width('100%')
                .padding(18)
                .borderRadius(16)
                .linearGradient({
                  angle: 135,
                  colors: [['#2EF5B841', 0], ['#145E8BFF', 1]]
                })
                .border({ width: 1, color: '#44F5B841' })

                Column({ space: 10 }) {
                  Text('Pro 核心专享权益')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))

                  this.benefitCard($r('app.media.ic_cloud_alist'), '无限 WebDAV / Alist / NAS 媒体源', '突破免费版 1 源上限，同时聚合阿里云盘、夸克与多台群晖')
                  this.benefitCard($r('app.media.ic_codec_hw'), '4K HDR 硬解与 FFmpeg 双核兜底', '原生 OH_AVPlayer 零拷贝硬解 + @ohos/ijkplayer 全封装兼容')
                  this.benefitCard($r('app.media.ic_file_subtitle'), 'ASS / SSA 特效与双语字幕引擎', '支持中英双语、顶部注解、延时精确微调与自动同目录加载')
                  this.benefitCard($r('app.media.ic_tmdb_clapboard'), '无限 TMDB 海报墙与智能合集', '自动区分电影/剧集季集分组，毫秒级断点跨屏续播')
                }.width('100%').alignItems(HorizontalAlign.Start)

                Column({ space: 10 }) {
                  Text('选择买断方案')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))

                  ForEach(this.products, (prod: IapProductDisplay, idx: number) => {
                    Row({ space: 12 }) {
                      Column({ space: 4 }) {
                        Row({ space: 8 }) {
                          Text(prod.title)
                          .fontSize(15)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.text_primary'))
                          Text(prod.badge)
                          .fontSize(10)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.Black)
                          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                          .borderRadius(5)
                          .backgroundColor($r('app.color.accent_gold'))
                        }
                        Text(prod.description)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      if (this.priceKnown) {
                        Column({ space: 2 }) {
                          if (prod.originalPriceText) {
                            Text(prod.originalPriceText)
                            .fontSize(12)
                            .fontColor($r('app.color.text_body_muted'))
                            .decoration({ type: TextDecorationType.LineThrough, color: $r('app.color.text_muted') })
                          }
                          Text(prod.priceText)
                          .fontSize(22)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.selectedIndex === idx ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
                        }
                        .alignItems(HorizontalAlign.End)
                      }
                    }
                    .width('100%')
                    .padding(16)
                    .borderRadius(14)
                    .backgroundColor(this.selectedIndex === idx ? $r('app.color.nav_active_bg') : $r('app.color.bg_elevated'))
                    .border({
                      width: this.selectedIndex === idx ? 1.6 : 0.8,
                      color: this.selectedIndex === idx ? $r('app.color.accent_blue') : $r('app.color.border_subtle')
                    })
                    .onClick(() => { this.selectedIndex = idx; })
                  }, (p: IapProductDisplay) => p.productId)
                }.width('100%').alignItems(HorizontalAlign.Start)

                if (this.statusMsg) {
                  Text(this.statusMsg)
                  .fontSize(12)
                  .fontColor($r('app.color.warning'))
                  .padding(12)
                  .width('100%')
                  .borderRadius(10)
                  .backgroundColor($r('app.color.bg_elevated'))
                }
              }
              .padding({ left: 18, right: 18, top: 14, bottom: 24 })
              .width('100%')
            }.edgeEffect(EdgeEffect.Spring)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)

            Row({ space: 12 }) {
              Button(this.buyLabel())
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.store.isPro ? $r('app.color.accent_gold') : Color.White)
              .backgroundColor(this.store.isPro ? '#24F5B841' : $r('app.color.accent_blue'))
              .borderRadius(12)
              .enabled(!this.busy && !this.store.isPro && this.iapSupported)
              .onClick(async () => {
                this.busy = true;
                const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                const prod = this.products[this.selectedIndex];
                const res = await IapService.purchase(ctx, prod);
                this.busy = false;
                this.statusMsg = res.message;
                if (res.success) {
                  await this.store.applyProTier(res.tier);
                }
              })
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 10, bottom: 18 })
            .backgroundColor($r('app.color.bar_glass'))
            .border({ width: { top: 0.6 }, color: $r('app.color.fill_subtle') })
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_primary'))
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

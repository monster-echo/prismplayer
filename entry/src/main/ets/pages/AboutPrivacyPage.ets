import { bundleManager } from '@kit.AbilityKit';
import { PageShell } from '../components/PageShell';
import { AppConstants } from '../common/Constants';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

@Entry
@ComponentV2
struct AboutPrivacyPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local versionText: string = '';

  aboutToAppear(): void {
    try {
      bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
        .then((info: bundleManager.BundleInfo) => {
          this.versionText = `v${info.versionName}`;
        })
        .catch(() => {});
    } catch (_e) {
      // 版本号读取失败不阻塞页面展示
    }
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '隐私安全与技术架构',
        subtitle: '本地优先架构 · 合规声明与开源许可',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 16 }) {
                Row({ space: 14 }) {
                  Image($r('app.media.ic_brand_prism')).width(52).height(52)
                  Column({ space: 3 }) {
                    Text('棱镜播放器 PrismPlayer').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                    Text(`HarmonyOS NEXT · 手机 / 平板 / 鸿蒙电脑跨端版${this.versionText ? ' · ' + this.versionText : ''}`)
                    .fontSize(12).fontColor($r('app.color.text_secondary'))
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })

                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    Image($r('app.media.ic_shield_vault')).width(20).height(20)
                    Text('隐私与 HUKS 凭据加密').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  }.width('100%')
                  Text('所有 NAS / WebDAV / Alist 账号与密码均通过系统硬件级密钥库（HUKS AES-256-GCM + AAD 认证标签）加密保存于本机，绝不上传至任何第三方服务器。')
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })
                .alignItems(HorizontalAlign.Start)

                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    Image($r('app.media.ic_cache_proxy')).width(20).height(20)
                    Text('C++ Native 代理诊断').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  }.width('100%')
                  Text(`Loopback Range Proxy：127.0.0.1:${this.store.proxyPort || '待启动'}`)
                  .fontSize(13)
                  .fontColor($r('app.color.accent_cyan'))
                  Text('运行模式：512 KB 块 LRU 内存缓存 + Alist 302 直链 TTL 10 分钟复用')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })
                .alignItems(HorizontalAlign.Start)

                Column({ space: 8 }) {
                  Text('第三方服务披露').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  Text('• 华为 IAP Kit：仅在您主动购买 Pro 买断权益时由华为处理支付流程，我们不获取您的支付账号信息。')
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.text_secondary'))
                  Text('• TMDB（The Movie Database）：仅在您主动配置 API Key 并开启刮削时按需请求影片名称查询，不含用户身份信息。')
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.text_secondary'))
                  Text('• SubDL / OpenSubtitles：仅在您主动搜索外挂字幕时发送影片名称与季集，用于检索字幕文件。')
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.text_secondary'))
                  Text('• 本应用不运营任何自有服务器，不含广告、统计或数据采集 SDK。')
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })
                .alignItems(HorizontalAlign.Start)

                Column({ space: 8 }) {
                  Text('开源组件许可声明').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  Text('• FFmpeg / @ohos/ijkplayer（LGPL v2.1+，动态共享库调用）')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  Text('• HarmonyOS NDK Media Kit（OH_AVPlayer / OH_AVMetadataExtractor）')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  Text('• Remote Communication Kit / Universal Keystore Kit (HUKS)')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })
                .alignItems(HorizontalAlign.Start)

                Column({ space: 8 }) {
                  Text('联系我们').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  Text(`开发者联系邮箱：${AppConstants.SUPPORT_EMAIL}`)
                  .fontSize(13)
                  .fontColor($r('app.color.accent_cyan'))
                  Text('如对隐私政策、用户协议或产品功能有任何疑问、意见或建议，欢迎通过邮件联系我们，我们将在十五个工作日内回复。')
                  .fontSize(12)
                  .lineHeight(19)
                  .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })
                .alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 18, right: 18, top: 14, bottom: 32 })
              .width('100%')
            }.edgeEffect(EdgeEffect.Spring)
            .layoutWeight(1)
            .width('100%')
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
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

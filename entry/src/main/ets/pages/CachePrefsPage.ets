import { AppSettings } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

/**
 * 「大文件与 4K 预缓冲」设置页（场景语言版）：
 * 滑杆 + 三个生活化档位锚点（省内存 / 均衡 / 极速），
 * 技术细节（512 KB LRU、Range 预读）全部下沉为灰色小字。
 */
@Entry
@ComponentV2
struct CachePrefsPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local cacheBudgetMb: number = 64;
  @Local savedTip: string = '';

  aboutToAppear(): void {
    this.cacheBudgetMb = this.store.settings.cacheBudgetMb;
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private async persist(): Promise<void> {
    const s = this.store.settings;
    const next: AppSettings = {
      themeMode: s.themeMode,
      cacheBudgetMb: this.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      subtitleFontSizeFp: s.subtitleFontSizeFp,
      subtitleLanguageMode: s.subtitleLanguageMode,
      subtitleBgEnabled: s.subtitleBgEnabled,
      subtitleBgOpacityPercent: s.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: s.subtitleVerticalOffsetVp,
      burnSubMaskDefault: s.burnSubMaskDefault,
      subdlApiKey: s.subdlApiKey,
      proTier: s.proTier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher || ''
    };
    await this.store.updateSettings(next);
    this.savedTip = '已保存';
    setTimeout(() => { this.savedTip = ''; }, 1400);
  }

  private tierOf(mb: number): string {
    if (mb <= 64) return 'saver';
    if (mb <= 128) return 'balance';
    return 'turbo';
  }

  private tierLabel(mb: number): string {
    const t = this.tierOf(mb);
    return t === 'saver' ? '省内存' : t === 'balance' ? '均衡' : '极速';
  }

  private tierHint(mb: number): string {
    const t = this.tierOf(mb);
    return t === 'saver'
      ? '日常剧集和在线影片足够用，内存占用最少'
      : t === 'balance'
        ? '4K 影片拖动进度条更顺滑'
        : '原盘和高码率 4K 来回拖动依然流畅';
  }

  private applySlider(value: number): void {
    const snapped = Math.max(32, Math.min(256, Math.round(value / 32) * 32));
    if (snapped !== this.cacheBudgetMb) {
      this.cacheBudgetMb = snapped;
    }
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '大文件与 4K 预缓冲',
        subtitle: this.savedTip || '拖动进度条更顺滑，起播更快',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 16 }) {
          // 预缓冲大小（滑杆 + 档位锚点）
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text('预缓冲大小')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.cacheBudgetMb} MB · ${this.tierLabel(this.cacheBudgetMb)}`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent_blue'))
            }
            .width('100%')

            Slider({
              value: this.cacheBudgetMb,
              min: 32,
              max: 256,
              step: 32
            })
              .selectedColor($r('app.color.accent_blue'))
              .trackColor($r('app.color.fill_subtle'))
              .blockColor($r('app.color.accent_blue'))
              .width('100%')
              .onChange((value: number, mode: SliderChangeMode) => {
                this.applySlider(value);
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.persist();
                }
              })

            Row({ space: 8 }) {
              Button('省内存（默认）')
                .layoutWeight(1.6)
                .height(38)
                .fontSize(11)
                .padding({ left: 2, right: 2 })
                .fontWeight(this.tierOf(this.cacheBudgetMb) === 'saver' ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.tierOf(this.cacheBudgetMb) === 'saver' ? Color.White : $r('app.color.text_secondary'))
                .backgroundColor(this.tierOf(this.cacheBudgetMb) === 'saver' ? $r('app.color.accent_blue') : $r('app.color.bg_secondary'))
                .borderRadius(10)
                .onClick(() => {
                  this.cacheBudgetMb = 64;
                  this.persist();
                })

              Button('均衡')
                .layoutWeight(1)
                .height(38)
                .fontSize(11)
                .padding({ left: 2, right: 2 })
                .fontWeight(this.tierOf(this.cacheBudgetMb) === 'balance' ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.tierOf(this.cacheBudgetMb) === 'balance' ? Color.White : $r('app.color.text_secondary'))
                .backgroundColor(this.tierOf(this.cacheBudgetMb) === 'balance' ? $r('app.color.accent_blue') : $r('app.color.bg_secondary'))
                .borderRadius(10)
                .onClick(() => {
                  this.cacheBudgetMb = 128;
                  this.persist();
                })

              Button('极速（适合原盘）')
                .layoutWeight(2)
                .height(38)
                .fontSize(11)
                .padding({ left: 2, right: 2 })
                .fontWeight(this.tierOf(this.cacheBudgetMb) === 'turbo' ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.tierOf(this.cacheBudgetMb) === 'turbo' ? Color.White : $r('app.color.text_secondary'))
                .backgroundColor(this.tierOf(this.cacheBudgetMb) === 'turbo' ? $r('app.color.accent_blue') : $r('app.color.bg_secondary'))
                .borderRadius(10)
                .onClick(() => {
                  this.cacheBudgetMb = 256;
                  this.persist();
                })
            }
            .width('100%')

            Text(this.tierHint(this.cacheBudgetMb))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))

            Text('技术细节：内容按 512 KB 分块缓存并自动淘汰最久未用的部分，避免大文件拖动时重复向服务器发起连接；仅在播放时占用内存，退出播放器后立即释放。')
              .fontSize(10)
              .lineHeight(15)
              .fontColor($r('app.color.text_muted'))
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)

          // 播放加速服务（场景语言，不暴露端口与实现）
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('播放加速服务')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Row({ space: 5 }) {
                Circle({ width: 7, height: 7 })
                  .fill(this.store.proxyPort > 0 ? $r('app.color.success') : $r('app.color.text_muted'))
                Text(this.store.proxyPort > 0 ? '运行中' : '待机')
                  .fontSize(12)
                  .fontColor(this.store.proxyPort > 0 ? $r('app.color.success') : $r('app.color.text_muted'))
              }
            }
            .width('100%')

            Text(
              this.store.proxyPort > 0
                ? '正在为本机播放的远程影片提供加速：起播更快、拖动进度条即时响应。关闭应用后自动停止。'
                : '首次播放远程影片时自动开启，为起播和进度条拖动提供本地加速，无需任何配置。'
            )
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 18, right: 18, top: 14, bottom: 32 })
        .width('100%')
      }
      .layoutWeight(1)
      .backgroundColor($r('app.color.bg_primary'))
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

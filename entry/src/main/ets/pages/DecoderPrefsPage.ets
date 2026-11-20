import { AppConstants } from '../common/Constants';
import { PageShell } from '../components/PageShell';
import { AppSettings, HardwareCodecRule } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

@Entry
@ComponentV2
struct DecoderPrefsPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local preferHw: boolean = true;
  @Local hwFormats: string[] = AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS.slice();
  @Local savedTip: string = '';

  aboutToAppear(): void {
    const s = this.store.settings;
    this.preferHw = s.preferHardwareDecode;
    this.hwFormats = (s.hardwareSupportedFormats && s.hardwareSupportedFormats.length > 0)
      ? s.hardwareSupportedFormats.slice()
      : AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS.slice();
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private isFormatHwEnabled(fmt: string): boolean {
    const target = fmt.toLowerCase();
    for (let i = 0; i < this.hwFormats.length; i++) {
      if (this.hwFormats[i].toLowerCase() === target) return true;
    }
    return false;
  }

  private toggleFormatHw(fmt: string): void {
    const target = fmt.toLowerCase();
    const exists = this.isFormatHwEnabled(target);
    const next: string[] = [];
    for (let i = 0; i < this.hwFormats.length; i++) {
      const cur = this.hwFormats[i].toLowerCase();
      if (cur !== target) {
        next.push(cur);
      }
    }
    if (!exists) {
      next.push(target);
    }
    this.hwFormats = next;
    this.persist();
  }

  private resetDefaultHwFormats(): void {
    this.hwFormats = AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS.slice();
    this.persist();
  }

  private async persist(): Promise<void> {
    const s = this.store.settings;
    const next: AppSettings = {
      themeMode: s.themeMode,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: this.preferHw,
      hardwareSupportedFormats: this.hwFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      autoSkipOutroSec: s.autoSkipOutroSec,
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

  build() {
    Column() {
      NavHeaderBar({
        title: '视频解码与硬解路由',
        subtitle: this.savedTip || '选择哪些格式走硬解，其余自动软解',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 16 }) {
                Row({ space: 12 }) {
                  Column({ space: 3 }) {
                    Text('优先使用系统硬件解码')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    Text('开启后按下方列表硬解，关闭则全部软解')
                    .fontSize(12)
                    .lineHeight(17)
                    .fontColor($r('app.color.text_muted'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                  Toggle({ type: ToggleType.Switch, isOn: this.preferHw })
                  .selectedColor($r('app.color.accent_blue'))
                  .onChange((v: boolean) => {
                    this.preferHw = v;
                    this.persist();
                  })
                }
                .width('100%')
                .padding(16)
                .borderRadius(12)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.7, color: $r('app.color.border_subtle') })

                Column({ space: 12 }) {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text('格式路由表')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      Text('开播前按列表选择引擎')
                      .fontSize(11)
                      .fontColor($r('app.color.text_muted'))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Text('恢复默认')
                    .fontSize(12)
                    .fontColor($r('app.color.accent_blue'))
                    .onClick(() => { this.resetDefaultHwFormats(); })
                  }.width('100%')

                  Column({ space: 8 }) {
                    ForEach(AppConstants.HARDWARE_CODEC_MATRIX, (rule: HardwareCodecRule) => {
                      Row({ space: 10 }) {
                        Column({ space: 2 }) {
                          Row({ space: 6 }) {
                            Text(rule.label)
                            .fontSize(13)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            Text(rule.format.toUpperCase())
                            .fontSize(10)
                            .fontColor($r('app.color.text_secondary'))
                            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                            .borderRadius(4)
                            .backgroundColor($r('app.color.divider'))
                          }
                          Text(rule.desc)
                          .fontSize(11)
                          .fontColor($r('app.color.text_muted'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)

                        Button(this.preferHw && this.isFormatHwEnabled(rule.format) ? '硬解' : 'FFmpeg 软解')
                        .height(28)
                        .padding({ left: 10, right: 10 })
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.preferHw && this.isFormatHwEnabled(rule.format) ? $r('app.color.success') : $r('app.color.text_secondary'))
                        .backgroundColor(this.preferHw && this.isFormatHwEnabled(rule.format) ? '#1810B981' : $r('app.color.bg_secondary'))
                        .border({
                          width: 0.7,
                          color: this.preferHw && this.isFormatHwEnabled(rule.format) ? '#4410B981' : $r('app.color.border_subtle')
                        })
                        .borderRadius(8)
                        .onClick(() => {
                          this.toggleFormatHw(rule.format);
                        })
                      }
                      .width('100%')
                      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                      .borderRadius(10)
                      .backgroundColor($r('app.color.bg_secondary'))
                    }, (rule: HardwareCodecRule) => `${rule.format}_${this.isFormatHwEnabled(rule.format)}`)
                  }.width('100%')
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
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

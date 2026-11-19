import { AppSettings } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

@Entry
@ComponentV2
struct SubtitlePrefsPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local fontSizeFp: number = 20;
  @Local bgEnabled: boolean = true;
  @Local bgOpacityPercent: number = 35;
  @Local verticalOffsetVp: number = 0;
  @Local savedTip: string = '';

  aboutToAppear(): void {
    const s = this.store.settings;
    this.fontSizeFp = s.subtitleFontSizeFp;
    this.bgEnabled = s.subtitleBgEnabled;
    this.bgOpacityPercent = s.subtitleBgOpacityPercent;
    this.verticalOffsetVp = s.subtitleVerticalOffsetVp;
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private previewBgColor(): string | Color {
    if (!this.bgEnabled) return Color.Transparent;
    const clamped = Math.min(100, Math.max(0, Math.round(this.bgOpacityPercent)));
    const alpha = Math.round(clamped * 255 / 100).toString(16).padStart(2, '0');
    return `#${alpha}000000`;
  }

  private async persist(): Promise<void> {
    const s = this.store.settings;
    const next: AppSettings = {
      themeMode: s.themeMode,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      subtitleFontSizeFp: this.fontSizeFp,
      subtitleLanguageMode: s.subtitleLanguageMode,
      subtitleBgEnabled: this.bgEnabled,
      subtitleBgOpacityPercent: this.bgOpacityPercent,
      subtitleVerticalOffsetVp: this.verticalOffsetVp,
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
        title: '字幕外观默认设置',
        subtitle: this.savedTip || '统一设置默认字号、背景底框与显示位置',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 16 }) {
          // Live Preview
          Column({ space: 4 }) {
            Column({ space: 2 }) {
              Text('海边的曼彻斯特')
                .fontSize(this.fontSizeFp)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .textShadow({ radius: 5, color: '#E6000000', offsetX: 0, offsetY: 1 })
                .textAlign(TextAlign.Center)
              Text('Manchester by the Sea')
                .fontSize(Math.max(12, Math.round(this.fontSizeFp * 0.78)))
                .fontColor('#E5E7EB')
                .textShadow({ radius: 5, color: '#E6000000', offsetX: 0, offsetY: 1 })
                .textAlign(TextAlign.Center)
            }
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(this.previewBgColor())
          }
          .width('100%')
          .padding({ top: 28, bottom: 28, left: 16, right: 16 })
          .borderRadius(12)
          .backgroundColor('#0F1117')
          .border({ width: 0.7, color: $r('app.color.border_subtle') })

          Column({ space: 14 }) {
            Row() {
              Text('默认字号').fontSize(14).fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.fontSizeFp} fp`).fontSize(13).fontColor($r('app.color.text_secondary'))
            }.width('100%')

            Slider({ value: this.fontSizeFp, min: 14, max: 32, step: 2 })
              .width('100%')
              .selectedColor($r('app.color.accent_blue'))
              .onChange((val: number) => {
                this.fontSizeFp = Math.round(val);
                this.persist();
              })

            Divider().color($r('app.color.divider'))

            Row() {
              Text('字幕半透明底框').fontSize(14).fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.bgEnabled })
                .selectedColor($r('app.color.accent_blue'))
                .onChange((v: boolean) => {
                  this.bgEnabled = v;
                  this.persist();
                })
            }.width('100%')

            if (this.bgEnabled) {
              Row() {
                Text('底框不透明度').fontSize(13).fontColor($r('app.color.text_secondary'))
                Blank()
                Text(`${this.bgOpacityPercent}%`).fontSize(13).fontColor($r('app.color.text_secondary'))
              }.width('100%')

              Slider({ value: this.bgOpacityPercent, min: 10, max: 85, step: 5 })
                .width('100%')
                .selectedColor($r('app.color.accent_blue'))
                .onChange((val: number) => {
                  this.bgOpacityPercent = Math.round(val);
                  this.persist();
                })
            }

            Divider().color($r('app.color.divider'))

            Row() {
              Text('底部抬升偏移').fontSize(14).fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.verticalOffsetVp} vp`).fontSize(13).fontColor($r('app.color.text_secondary'))
            }.width('100%')

            Slider({ value: this.verticalOffsetVp, min: 0, max: 80, step: 4 })
              .width('100%')
              .selectedColor($r('app.color.accent_blue'))
              .onChange((val: number) => {
                this.verticalOffsetVp = Math.round(val);
                this.persist();
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.border_subtle') })
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

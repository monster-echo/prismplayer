import { AppConstants } from '../common/Constants';
import { PageShell } from '../components/PageShell';
import { AppSettings } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

@Entry
@ComponentV2
struct TmdbConfigPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local tmdbKey: string = '';
  @Local tmdbHost: string = AppConstants.DEFAULT_TMDB_HOST;
  @Local statusText: string = '';

  aboutToAppear(): void {
    this.tmdbKey = this.store.settings.tmdbApiKey;
    this.tmdbHost = this.store.settings.tmdbApiHost || AppConstants.DEFAULT_TMDB_HOST;
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private async saveConfig(): Promise<void> {
    const s = this.store.settings;
    const next: AppSettings = {
      themeMode: s.themeMode,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: this.tmdbKey.trim(),
      tmdbApiHost: this.tmdbHost.trim() || AppConstants.DEFAULT_TMDB_HOST,
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
    this.statusText = 'TMDB 刮削配置已保存';
  }

  build() {
    Column() {
      NavHeaderBar({
        title: 'TMDB 海报墙刮削',
        subtitle: 'NFO 本地优先 + 在线精准海报/简介补全',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 18 }) {
                Row({ space: 12 }) {
                  Image($r('app.media.ic_tmdb_clapboard')).width(34).height(34)
                  Column({ space: 3 }) {
                    Text('智能双路元数据引擎').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                    Text('优先读取同目录 .nfo 与本地字幕，留空 Key 也可依据文件名生成精美影库墙')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor($r('app.color.text_secondary'))
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor('#1A8B5CF6')
                .border({ width: 0.8, color: '#38A78BFA' })

                Column({ space: 12 }) {
                  Text('TMDB v3 API Key（个人免费申请）')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))

                  TextInput({ text: this.tmdbKey, placeholder: '输入 TMDB v3 API Key（留空仅启用本地 NFO/文件名解析）' })
                  .height(44)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onChange((v: string) => { this.tmdbKey = v; })

                  Text('API 接口地址 / 自建反代镜像')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))

                  TextInput({ text: this.tmdbHost, placeholder: AppConstants.DEFAULT_TMDB_HOST })
                  .height(44)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onChange((v: string) => { this.tmdbHost = v; })

                  Row({ space: 8 }) {
                    Button('恢复官方域名')
                    .height(34)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .backgroundColor($r('app.color.bg_secondary'))
                    .borderRadius(8)
                    .onClick(() => { this.tmdbHost = AppConstants.DEFAULT_TMDB_HOST; })

                    Blank()

                    Button('保存配置')
                    .height(36)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .backgroundColor($r('app.color.accent_blue'))
                    .borderRadius(8)
                    .onClick(() => { this.saveConfig(); })
                  }.width('100%')

                  if (this.statusText) {
                    Text(this.statusText)
                    .fontSize(12)
                    .fontColor($r('app.color.success'))
                    .width('100%')
                  }
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
            }
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

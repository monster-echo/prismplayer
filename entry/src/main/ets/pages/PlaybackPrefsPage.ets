import { AppConstants, PC_SHORTCUTS, ShortcutTip } from '../common/Constants';
import { AppSettings, HardwareCodecRule, SubtitleLanguageMode } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

@Entry
@ComponentV2
struct PlaybackPrefsPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local preferHw: boolean = true;
  @Local hwFormats: string[] = AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS.slice();
  @Local showHwMatrix: boolean = true;
  @Local cacheBudgetMb: number = 64;
  @Local fontSizeFp: number = 20;
  @Local languageMode: SubtitleLanguageMode = 'all';
  @Local subtitleBgEnabled: boolean = true;
  @Local subtitleBgOpacity: number = 35;
  @Local subtitleOffsetVp: number = 0;
  @Local burnSubMaskDefault: boolean = false;
  @Local savedTip: string = '';
  @Local showShortcuts: boolean = false;

  aboutToAppear(): void {
    const s = this.store.settings;
    this.preferHw = s.preferHardwareDecode;
    this.hwFormats = (s.hardwareSupportedFormats && s.hardwareSupportedFormats.length > 0)
      ? s.hardwareSupportedFormats.slice()
      : AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS.slice();
    this.cacheBudgetMb = s.cacheBudgetMb;
    this.fontSizeFp = s.subtitleFontSizeFp;
    this.languageMode = s.subtitleLanguageMode;
    this.subtitleBgEnabled = s.subtitleBgEnabled;
    this.subtitleBgOpacity = s.subtitleBgOpacityPercent;
    this.subtitleOffsetVp = s.subtitleVerticalOffsetVp;
    this.burnSubMaskDefault = s.burnSubMaskDefault;
  }

  private previewBubbleBg(): string | Color {
    if (!this.subtitleBgEnabled) return Color.Transparent;
    const clamped = Math.min(100, Math.max(0, Math.round(this.subtitleBgOpacity)));
    const alpha = Math.round(clamped * 255 / 100).toString(16).padStart(2, '0');
    return `#${alpha}000000`;
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

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private async persist(): Promise<void> {
    const s = this.store.settings;
    const next: AppSettings = {
      themeMode: s.themeMode,
      cacheBudgetMb: this.cacheBudgetMb,
      preferHardwareDecode: this.preferHw,
      hardwareSupportedFormats: this.hwFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      subtitleFontSizeFp: this.fontSizeFp,
      subtitleLanguageMode: this.languageMode,
      subtitleBgEnabled: this.subtitleBgEnabled,
      subtitleBgOpacityPercent: this.subtitleBgOpacity,
      subtitleVerticalOffsetVp: this.subtitleOffsetVp,
      burnSubMaskDefault: this.burnSubMaskDefault,
      subdlApiKey: s.subdlApiKey,
      proTier: s.proTier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher || ''
    };
    await this.store.updateSettings(next);
    this.savedTip = '已生效';
    setTimeout(() => { this.savedTip = ''; }, 1500);
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '解码、缓存与字幕偏好',
        subtitle: this.savedTip || '实时保存播放内核与 C++ 代理参数',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 18 }) {
          // Decoder Engine
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_codec_hw')).width(22).height(22)
              Text('视频解码内核').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            }.width('100%')

            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text('优先使用系统硬件解码（OH_AVPlayer）').fontSize(14).fontColor($r('app.color.text_primary'))
                Text('开启后硬解 4K HEVC / H.264；若遇不支持封装将自动切换 FFmpeg 软解').fontSize(11).lineHeight(16).fontColor($r('app.color.text_muted'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.preferHw })
                .selectedColor($r('app.color.accent_blue'))
                .onChange((v: boolean) => {
                  this.preferHw = v;
                  this.persist();
                })
            }.width('100%')

            Divider().color($r('app.color.fill_subtle'))

            // hardwareSupportedFormats Routing Matrix
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text('智能硬解 / 软解格式路由表 (hardwareSupportedFormats)')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text('播放前直接匹配列表：列表中格式直通 OH_AVPlayer 硬解，其余格式直接启动 FFmpeg 软解，避免中途报错闪切')
                  .fontSize(11)
                  .lineHeight(15)
                  .fontColor($r('app.color.text_muted'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text('恢复默认')
                .fontSize(11)
                .fontColor($r('app.color.accent_cyan'))
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
                        .fontColor($r('app.color.accent_cyan'))
                        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        .borderRadius(4)
                        .backgroundColor('#1A38BDF8')
                    }
                    Text(rule.desc)
                      .fontSize(11)
                      .fontColor($r('app.color.text_muted'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button(this.preferHw && this.isFormatHwEnabled(rule.format) ? '硬解 OH_AVPlayer' : '软解 FFmpeg')
                    .height(28)
                    .padding({ left: 10, right: 10 })
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.preferHw && this.isFormatHwEnabled(rule.format) ? $r('app.color.success') : $r('app.color.accent_gold'))
                    .backgroundColor(this.preferHw && this.isFormatHwEnabled(rule.format) ? '#1A34D399' : '#1AF5B841')
                    .border({
                      width: 0.7,
                      color: this.preferHw && this.isFormatHwEnabled(rule.format) ? '#5534D399' : '#55F5B841'
                    })
                    .borderRadius(8)
                    .onClick(() => {
                      this.toggleFormatHw(rule.format);
                    })
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .borderRadius(10)
                .backgroundColor($r('app.color.bg_secondary'))
              }, (rule: HardwareCodecRule) => `${rule.format}_${this.isFormatHwEnabled(rule.format)}`)
            }.width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)

          // C++ Range Proxy Memory Budget
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_cache_proxy')).width(22).height(22)
              Text('C++ HTTP Range 预读块缓存').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            }.width('100%')

            Text('按 512 KB 块粒度实行 LRU 内存淘汰，拖动大体积 MKV 进度条时减少重复建连')
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))

            Row({ space: 10 }) {
              ForEach([32, 64, 128], (mb: number) => {
                Button(`${mb} MB`)
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .fontWeight(this.cacheBudgetMb === mb ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.cacheBudgetMb === mb ? Color.White : $r('app.color.text_secondary'))
                  .backgroundColor(this.cacheBudgetMb === mb ? $r('app.color.accent_blue') : $r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onClick(() => {
                    this.cacheBudgetMb = mb;
                    this.persist();
                  })
              }, (mb: number) => `${mb}`)
            }.width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)

          // Subtitle Style Defaults + Live Cinema Preview
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_file_subtitle')).width(22).height(22)
              Text(`字幕样式默认值 · ${this.fontSizeFp} fp`).fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            }.width('100%')

            Column({ space: 4 }) {
              if (this.languageMode !== 'en') {
                Text('海边的曼彻斯特')
                  .fontSize(this.fontSizeFp)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .textShadow({ radius: 6, color: '#E6000000', offsetX: 0, offsetY: 2 })
                  .textAlign(TextAlign.Center)
                  .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                  .borderRadius(6)
                  .backgroundColor(this.previewBubbleBg())
              }
              if (this.languageMode !== 'zh') {
                Text('Manchester by the Sea')
                  .fontSize(Math.max(12, Math.round(this.fontSizeFp * 0.78)))
                  .fontColor($r('app.color.accent_gold'))
                  .textShadow({ radius: 6, color: '#E6000000', offsetX: 0, offsetY: 2 })
                  .textAlign(TextAlign.Center)
                  .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                  .borderRadius(6)
                  .backgroundColor(this.previewBubbleBg())
              }
            }
            .width('100%')
            .padding({ top: 18, bottom: 18, left: 12, right: 12 })
            .borderRadius(12)
            .linearGradient({
              angle: 135,
              colors: [['#151D30', 0], ['#0B0D14', 1]]
            })
            .border({ width: 0.6, color: $r('app.color.fill_strong') })

            Slider({ value: this.fontSizeFp, min: 14, max: 32, step: 2 })
              .width('100%')
              .selectedColor($r('app.color.accent_blue'))
              .onChange((val: number) => {
                this.fontSizeFp = Math.round(val);
                this.persist();
              })

            Divider().color($r('app.color.fill_subtle'))

            Text('显示语言').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
            Row({ space: 8 }) {
              ForEach(['all', 'zh', 'en'] as SubtitleLanguageMode[], (m: SubtitleLanguageMode) => {
                Button(m === 'all' ? '全部' : (m === 'zh' ? '只中文' : '只英文'))
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .fontWeight(this.languageMode === m ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.languageMode === m ? Color.White : $r('app.color.text_secondary'))
                  .backgroundColor(this.languageMode === m ? $r('app.color.accent_blue') : $r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onClick(() => {
                    this.languageMode = m;
                    this.persist();
                  })
              }, (m: SubtitleLanguageMode) => `${m}_${this.languageMode === m}`)
            }.width('100%')
            Text('双语字幕按行过滤：含中文的行为中文行，其余为英文行；多轨可同时启用')
              .fontSize(11)
              .lineHeight(15)
              .fontColor($r('app.color.text_muted'))

            Divider().color($r('app.color.fill_subtle'))

            Row() {
              Column({ space: 3 }) {
                Text('字幕背景').fontSize(14).fontColor($r('app.color.text_primary'))
                Text('关闭后仅保留描边阴影，适合浅色画面')
                  .fontSize(11)
                  .fontColor($r('app.color.text_muted'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.subtitleBgEnabled })
                .selectedColor($r('app.color.accent_blue'))
                .onChange((v: boolean) => {
                  this.subtitleBgEnabled = v;
                  this.persist();
                })
            }.width('100%')

            Text(`背景不透明度：${this.subtitleBgOpacity}%`).fontSize(12).fontColor($r('app.color.text_secondary'))
            Slider({ value: this.subtitleBgOpacity, min: 0, max: 100, step: 5 })
              .width('100%')
              .selectedColor($r('app.color.accent_blue'))
              .onChange((val: number) => {
                this.subtitleBgOpacity = Math.round(val);
                this.persist();
              })

            Divider().color($r('app.color.fill_subtle'))

            Text(this.subtitleOffsetVp === 0 ? '字幕位置：默认底部' : `字幕位置：上移 ${this.subtitleOffsetVp}vp`)
              .fontSize(12).fontColor($r('app.color.text_secondary'))
            Slider({ value: this.subtitleOffsetVp, min: 0, max: 160, step: 8 })
              .width('100%')
              .selectedColor($r('app.color.accent_blue'))
              .onChange((val: number) => {
                this.subtitleOffsetVp = Math.round(val);
                this.persist();
              })

            Divider().color($r('app.color.fill_subtle'))

            Row() {
              Column({ space: 3 }) {
                Text('默认遮挡内嵌字幕').fontSize(14).fontColor($r('app.color.text_primary'))
                Text('英语学习模式：播放视频时默认盖住画面里烧录的硬字幕（可按视频单独关闭）')
                  .fontSize(11)
                  .fontColor($r('app.color.text_muted'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.burnSubMaskDefault })
                .selectedColor($r('app.color.accent_blue'))
                .onChange((v: boolean) => {
                  this.burnSubMaskDefault = v;
                  this.persist();
                })
            }.width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)

          // Collapsible HarmonyOS PC Shortcuts Card
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_keyboard_pc')).width(22).height(22)
              Text('鸿蒙电脑（2in1）快捷键').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).layoutWeight(1)
              Text(`${PC_SHORTCUTS.length} 项`).fontSize(12).fontColor($r('app.color.text_muted'))
              SymbolGlyph(this.showShortcuts ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                .fontSize(13)
                .fontColor([$r('app.color.text_muted')])
            }
            .width('100%')
            .onClick(() => { this.showShortcuts = !this.showShortcuts; })

            if (this.showShortcuts) {
              Divider().color($r('app.color.divider'))
              ForEach(PC_SHORTCUTS, (tip: ShortcutTip) => {
                Row() {
                  Text(tip.keys)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.accent_cyan'))
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(6)
                    .backgroundColor($r('app.color.bg_secondary'))
                  Blank()
                  Text(tip.action)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                }.width('100%')
              }, (tip: ShortcutTip) => tip.keys)
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

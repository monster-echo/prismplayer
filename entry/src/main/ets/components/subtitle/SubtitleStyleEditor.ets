import { SubtitleLanguageMode } from '../../common/Types';
import { SubtitleChip, SubtitleSectionHeader, SubtitleToggleRow } from './SubtitleUi';

/**
 * Shared subtitle appearance editor used by both:
 *  - the in-player "字幕样式" screen (live session values), and
 *  - the settings "字幕默认样式" page (persisted defaults).
 *
 * This is the only place where font size, background, opacity, position and bilingual
 * filtering are edited, so the two entry points can never drift again.
 */
@ComponentV2
export struct SubtitleStyleEditor {
  @Param fontSizeFp: number = 20;
  @Param bgEnabled: boolean = true;
  @Param bgOpacityPercent: number = 35;
  @Param verticalOffsetVp: number = 0;
  @Param languageMode: SubtitleLanguageMode = 'all';
  @Param showLanguageFilter: boolean = false;
  @Param previewTitle: string = '海边的曼彻斯特';
  @Param previewSubtitle: string = 'Manchester by the Sea';

  @Param onFontSizeChange: (value: number) => void = (_value: number) => {};
  @Param onFontSizeCommit: () => void = () => {};
  @Param onBgToggle: (value: boolean) => void = (_value: boolean) => {};
  @Param onBgOpacityChange: (value: number) => void = (_value: number) => {};
  @Param onBgOpacityCommit: () => void = () => {};
  @Param onOffsetChange: (value: number) => void = (_value: number) => {};
  @Param onOffsetCommit: () => void = () => {};
  @Param onLanguageMode: (mode: SubtitleLanguageMode) => void = (_mode: SubtitleLanguageMode) => {};

  private bubbleBgColor(): string | Color {
    if (!this.bgEnabled) return Color.Transparent;
    const clamped = Math.min(100, Math.max(0, Math.round(this.bgOpacityPercent)));
    const alpha = Math.round(clamped * 255 / 100).toString(16).padStart(2, '0');
    return `#${alpha}000000`;
  }

  private showChineseLine(): boolean {
    return this.languageMode !== 'en';
  }

  private showEnglishLine(): boolean {
    return this.languageMode !== 'zh';
  }

  private previewBottomPad(): number {
    return 18 + Math.min(96, Math.max(0, Math.round(this.verticalOffsetVp)));
  }

  private offsetLabel(): string {
    return this.verticalOffsetVp === 0 ? '默认底部' : `上移 ${this.verticalOffsetVp} vp`;
  }

  @Builder
  numberRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#E5E7EB')
      Blank()
      Text(value).fontSize(12).fontColor('#9CA3AF')
    }
    .width('100%')
  }

  build() {
    Column({ space: 16 }) {
      // Live preview against a neutral "video" frame.
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height(196)
          .linearGradient({ angle: 135, colors: [['#23324A', 0], ['#0B1220', 0.6], ['#070A10', 1]] })

        Text('字幕预览')
          .fontSize(10)
          .fontColor('#94A3B8')
          .padding({ left: 12, top: 10 })
          .position({ x: 0, y: 0 })

        if (this.showChineseLine() || this.showEnglishLine()) {
          Column({ space: 2 }) {
            if (this.showChineseLine()) {
              Text(this.previewTitle)
                .fontSize(this.fontSizeFp)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .textShadow({ radius: 5, color: '#E6000000', offsetX: 0, offsetY: 1 })
                .textAlign(TextAlign.Center)
            }
            if (this.showEnglishLine()) {
              Text(this.previewSubtitle)
                .fontSize(Math.max(12, Math.round(this.fontSizeFp * 0.78)))
                .fontColor('#E5E7EB')
                .textShadow({ radius: 5, color: '#E6000000', offsetX: 0, offsetY: 1 })
                .textAlign(TextAlign.Center)
            }
          }
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(8)
          .backgroundColor(this.bubbleBgColor())
          .margin({ left: 16, right: 16, bottom: this.previewBottomPad() })
        } else {
          Text('当前过滤条件下没有可显示的字幕行')
            .fontSize(11)
            .fontColor('#94A3B8')
            .margin({ bottom: 18 })
        }
      }
      .width('100%')
      .height(196)
      .borderRadius(12)
      .clip(true)
      .border({ width: 0.7, color: '#1FFFFFFF' })

      Column({ space: 12 }) {
        this.numberRow('字号', `${this.fontSizeFp} fp`)
        Slider({ value: this.fontSizeFp, min: 14, max: 32, step: 2 })
          .width('100%')
          .selectedColor('#3B82F6')
          .onChange((v: number, mode: SliderChangeMode) => {
            this.onFontSizeChange(Math.round(v));
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onFontSizeCommit();
            }
          })

        if (this.showLanguageFilter) {
          Divider().color('#1FFFFFFF')
          SubtitleSectionHeader({ title: '双语字幕行过滤', note: '按语言筛选双语字幕行；这里的选择会保存为默认' })
          Row({ space: 8 }) {
            ForEach(['all', 'zh', 'en'] as SubtitleLanguageMode[], (m: SubtitleLanguageMode) => {
              SubtitleChip({
                label: m === 'all' ? '中英都显示' : (m === 'zh' ? '只看中文' : '只看英文'),
                active: this.languageMode === m,
                onTap: () => this.onLanguageMode(m)
              })
            }, (m: SubtitleLanguageMode) => `style_lang_${m}_${this.languageMode === m}`)
          }
          .width('100%')
        }

        Divider().color('#1FFFFFFF')
        SubtitleToggleRow({
          title: '半透明底框',
          desc: '在字幕文字后垫一层黑色底，提升亮场景可读性',
          value: this.bgEnabled,
          onChange: (v: boolean) => this.onBgToggle(v)
        })

        if (this.bgEnabled) {
          this.numberRow('底框不透明度', `${this.bgOpacityPercent}%`)
          Slider({ value: this.bgOpacityPercent, min: 0, max: 100, step: 5 })
            .width('100%')
            .selectedColor('#3B82F6')
            .onChange((v: number, mode: SliderChangeMode) => {
              this.onBgOpacityChange(Math.round(v));
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.onBgOpacityCommit();
              }
            })
        }

        Divider().color('#1FFFFFFF')
        this.numberRow('字幕位置', this.offsetLabel())
        Slider({ value: this.verticalOffsetVp, min: 0, max: 160, step: 8 })
          .width('100%')
          .selectedColor('#3B82F6')
          .onChange((v: number, mode: SliderChangeMode) => {
            this.onOffsetChange(Math.round(v));
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.onOffsetCommit();
            }
          })
        Text('数值越大，字幕整体越靠上；默认 0 为画面底部安全区。')
          .fontSize(10)
          .lineHeight(15)
          .fontColor('#6B7280')
      }
      .width('100%')
      .padding(16)
      .borderRadius(14)
      .backgroundColor('#14161D')
      .border({ width: 0.7, color: '#1FFFFFFF' })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }
}

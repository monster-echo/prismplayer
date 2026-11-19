import { SubtitleCue, SubtitleLanguageMode } from '../common/Types';
import { SubtitleEngine } from '../services/SubtitleEngine';

@ComponentV2
export struct SubtitleOverlay {
  @Param cues: SubtitleCue[] = [];
  @Param fontSizeFp: number = 20;
  @Param languageMode: SubtitleLanguageMode = 'all';
  @Param bgEnabled: boolean = true;
  @Param bgOpacityPercent: number = 35;
  @Param verticalOffsetVp: number = 0;

  private getFilteredText(cue: SubtitleCue): string {
    return SubtitleEngine.filterCueLines(cue.text, this.languageMode);
  }

  private hasVisibleText(cue: SubtitleCue): boolean {
    return this.getFilteredText(cue).length > 0;
  }

  private getTopCues(): SubtitleCue[] {
    return this.cues.filter(c => c.alignment >= 7 && c.alignment <= 9 && this.hasVisibleText(c));
  }

  private getMiddleCues(): SubtitleCue[] {
    return this.cues.filter(c => c.alignment >= 4 && c.alignment <= 6 && this.hasVisibleText(c));
  }

  private getBottomCues(): SubtitleCue[] {
    return this.cues.filter(c => c.alignment <= 3 && this.hasVisibleText(c));
  }

  private bubbleBackgroundColor(): string | Color {
    if (!this.bgEnabled) return Color.Transparent;
    const clamped = Math.min(100, Math.max(0, Math.round(this.bgOpacityPercent)));
    const alpha = Math.round(clamped * 255 / 100).toString(16).padStart(2, '0');
    return `#${alpha}000000`;
  }

  @Builder
  renderCueBubble(cue: SubtitleCue) {
    Text(this.getFilteredText(cue))
      .fontSize(this.fontSizeFp)
      .fontWeight(cue.isBold ? FontWeight.Bold : FontWeight.Medium)
      .fontStyle(cue.isItalic ? FontStyle.Italic : FontStyle.Normal)
      .fontColor(cue.colorHex || '#FFFFFF')
      .textAlign(TextAlign.Center)
      .textShadow({
        radius: 4,
        color: '#E6000000',
        offsetX: 1,
        offsetY: 1
      })
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .borderRadius(6)
      .backgroundColor(this.bubbleBackgroundColor())
  }

  build() {
    if (this.cues.length > 0) {
      Column() {
        // Top cues (ASS \an7, \an8, \an9)
        Column({ space: 4 }) {
          ForEach(this.getTopCues(), (cue: SubtitleCue) => {
            this.renderCueBubble(cue);
          }, (cue: SubtitleCue) => `${cue.index}_${cue.startMs}`)
        }
        .width('100%')
        .padding({ top: 76, left: 24, right: 24 })
        .alignItems(HorizontalAlign.Center)

        Blank()

        // Middle cues (ASS \an4, \an5, \an6)
        Column({ space: 4 }) {
          ForEach(this.getMiddleCues(), (cue: SubtitleCue) => {
            this.renderCueBubble(cue);
          }, (cue: SubtitleCue) => `${cue.index}_${cue.startMs}`)
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .alignItems(HorizontalAlign.Center)

        Blank()

        // Bottom cues (ASS \an1, \an2, \an3 + SRT/VTT)
        Column({ space: 4 }) {
          ForEach(this.getBottomCues(), (cue: SubtitleCue) => {
            this.renderCueBubble(cue);
          }, (cue: SubtitleCue) => `${cue.index}_${cue.startMs}`)
        }
        .width('100%')
        .padding({ bottom: 68 + this.verticalOffsetVp, left: 24, right: 24 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }
}

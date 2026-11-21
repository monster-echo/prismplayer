import { SubtitleLanguageMode, SubtitleStyleValues } from '../common/Types';
import { PageShell } from '../components/PageShell';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { SubtitleStyleEditor } from '../components/subtitle/SubtitleStyleEditor';
import { AppStore } from '../services/AppStore';
import { SubtitleSession } from '../services/SubtitleSession';

/**
 * Settings entry: subtitle appearance defaults only.
 * Shares the exact editor used by the in-player "字幕样式" screen, so there is one
 * implementation of font size / background / opacity / position / bilingual filtering.
 */
@Entry
@ComponentV2
struct SubtitlePrefsPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Local fontSizeFp: number = 20;
  @Local bgEnabled: boolean = true;
  @Local bgOpacityPercent: number = 35;
  @Local verticalOffsetVp: number = 0;
  @Local languageMode: SubtitleLanguageMode = 'all';
  @Local savedTip: string = '';

  aboutToAppear(): void {
    const s = this.store.settings;
    this.fontSizeFp = s.subtitleFontSizeFp;
    this.bgEnabled = s.subtitleBgEnabled;
    this.bgOpacityPercent = s.subtitleBgOpacityPercent;
    this.verticalOffsetVp = s.subtitleVerticalOffsetVp;
    this.languageMode = s.subtitleLanguageMode;
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private async persist(): Promise<void> {
    const style: SubtitleStyleValues = {
      fontSizeFp: this.fontSizeFp,
      bgEnabled: this.bgEnabled,
      bgOpacityPercent: this.bgOpacityPercent,
      verticalOffsetVp: this.verticalOffsetVp,
      languageMode: this.languageMode
    };
    await this.store.saveSubtitleDefaults(style);
    if (this.session.active) {
      this.session.syncStyleFromPreferences();
    }
    this.savedTip = '已保存';
    setTimeout(() => { this.savedTip = ''; }, 1400);
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '字幕默认样式',
        subtitle: this.savedTip || '新视频沿用这套样式',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 16 }) {
                SubtitleStyleEditor({
                  fontSizeFp: this.fontSizeFp,
                  bgEnabled: this.bgEnabled,
                  bgOpacityPercent: this.bgOpacityPercent,
                  verticalOffsetVp: this.verticalOffsetVp,
                  languageMode: this.languageMode,
                  showLanguageFilter: true,
                  onFontSizeChange: (v: number) => { this.fontSizeFp = v; },
                  onFontSizeCommit: () => this.persist(),
                  onBgToggle: (v: boolean) => {
                    this.bgEnabled = v;
                    this.persist();
                  },
                  onBgOpacityChange: (v: number) => { this.bgOpacityPercent = v; },
                  onBgOpacityCommit: () => this.persist(),
                  onOffsetChange: (v: number) => { this.verticalOffsetVp = v; },
                  onOffsetCommit: () => this.persist(),
                  onLanguageMode: (m: SubtitleLanguageMode) => {
                    this.languageMode = m;
                    this.persist();
                  }
                })

              }
              .padding({ left: 18, right: 18, top: 10, bottom: 36 })
              .width('100%')
            }.edgeEffect(EdgeEffect.Spring)
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

import { SubtitleLanguageMode } from '../../common/Types';
import { SubtitleSession } from '../../services/SubtitleSession';
import { SubtitleStyleEditor } from './SubtitleStyleEditor';
import { SubtitlePageHeader } from './SubtitleUi';

/**
 * One responsibility: how subtitles look.
 * Uses the shared editor so the settings page and the in-player screen cannot diverge.
 */
@ComponentV2
export struct SubtitleStylePage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};

  build() {
    Column() {
      SubtitlePageHeader({
        title: '字幕样式',
        caption: '修改实时生效，并保存为后续视频的默认样式',
        onBack: () => this.onBack(),
        onClose: () => this.onClose()
      })

      Scroll() {
        Column({ space: 14 }) {
          SubtitleStyleEditor({
            fontSizeFp: this.session.fontFp,
            bgEnabled: this.session.bgEnabled,
            bgOpacityPercent: this.session.bgOpacityPercent,
            verticalOffsetVp: this.session.verticalOffsetVp,
            languageMode: this.session.languageMode,
            showLanguageFilter: this.session.hasBilingualTrack(),
            onFontSizeChange: (v: number) => this.session.previewFontSize(v),
            onFontSizeCommit: () => this.session.commitStyleDefaults(),
            onBgToggle: (v: boolean) => this.session.setBgEnabled(v),
            onBgOpacityChange: (v: number) => this.session.previewBgOpacity(v),
            onBgOpacityCommit: () => this.session.commitStyleDefaults(),
            onOffsetChange: (v: number) => this.session.previewVerticalOffset(v),
            onOffsetCommit: () => this.session.commitStyleDefaults(),
            onLanguageMode: (m: SubtitleLanguageMode) => this.session.setLanguageMode(m)
          })

          Text('字幕样式是全局默认值：这里与设置页编辑的是同一套数据，调整后新打开的视频都会沿用。')
            .fontSize(10)
            .lineHeight(16)
            .fontColor('#6B7280')
            .padding({ left: 4, right: 4 })
        }
        .padding({ left: 18, right: 18, top: 8, bottom: 36 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF0B0D12')
  }
}

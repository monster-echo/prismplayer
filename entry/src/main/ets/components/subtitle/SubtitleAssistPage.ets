import { SubtitleService } from '../../services/SubtitleService';
import { SubtitleSession } from '../../services/SubtitleSession';
import {
  SubtitlePageHeader,
  SubtitleSectionHeader,
  SubtitleToggleRow
} from './SubtitleUi';

/**
 * One responsibility: language assistance on top of the mounted subtitle.
 * Translation and read-aloud are two switches over the same cue stream, so they share one screen.
 */
@ComponentV2
export struct SubtitleAssistPage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};

  private hasExternalTrack(): boolean {
    return this.session.externalTracks.length > 0;
  }

  build() {
    Column() {
      SubtitlePageHeader({
        title: '翻译与朗读',
        caption: '仅对外挂字幕生效',
        onBack: () => this.onBack(),
        onClose: () => this.onClose()
      })

      Scroll() {
        Column({ space: 16 }) {
          if (!this.hasExternalTrack()) {
            Column({ space: 6 }) {
              Text('还没有外挂字幕').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E5E7EB')
              Text('先在「字幕轨道」导入或在线匹配。')
                .fontSize(11)
                .lineHeight(17)
                .fontColor('#9CA3AF')
            }
            .width('100%')
            .padding(16)
            .borderRadius(14)
            .backgroundColor('#1A3B82F6')
            .border({ width: 0.7, color: '#333B82F6' })
            .alignItems(HorizontalAlign.Start)
          }

          Column({ space: 12 }) {
            SubtitleSectionHeader({
              title: '外文字幕翻译为中文',
              note: '外文台词显示中文译文，保留原文'
            })
            SubtitleToggleRow({
              title: '开启翻译',
              desc: '外挂字幕均可翻译',
              value: this.session.translateEnabled,
              interactive: this.hasExternalTrack(),
              onChange: (v: boolean) => this.session.setTranslateEnabled(v)
            })
            if (this.session.translateEnabled) {
              Text('当前字幕：' + (this.session.currentCueText ? this.session.currentCueText : '等待下一句...'))
                .fontSize(11)
                .lineHeight(17)
                .fontColor('#93C5FD')
                .width('100%')
                .padding(10)
                .borderRadius(8)
                .backgroundColor('#101218')
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 12 }) {
            SubtitleSectionHeader({
              title: 'AI 语音朗读字幕',
              note: '系统语音朗读当前字幕'
            })
            SubtitleToggleRow({
              title: '开启朗读',
              desc: '关闭后立即停止',
              value: this.session.ttsEnabled,
              interactive: this.hasExternalTrack(),
              onChange: (v: boolean) => this.session.setTtsEnabled(v)
            })
            if (this.session.ttsEnabled) {
              Button('立即停止朗读')
                .width('100%')
                .height(36)
                .fontSize(12)
                .fontColor('#FCA5A5')
                .backgroundColor('#1AF87171')
                .borderRadius(9)
                .onClick(() => {
                  this.session.setTtsEnabled(false);
                  SubtitleService.stopSpeaking();
                })
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Text('翻译仅发送当前字幕文本；内嵌字幕不参与。')
            .fontSize(10)
            .lineHeight(16)
            .fontColor('#6B7280')
            .padding({ left: 4, right: 4 })
        }
        .padding({ left: 18, right: 18, top: 8, bottom: 36 })
        .width('100%')
      }.edgeEffect(EdgeEffect.Spring)
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

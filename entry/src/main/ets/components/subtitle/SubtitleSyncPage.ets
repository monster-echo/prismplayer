import { SubtitleSession } from '../../services/SubtitleSession';
import { SubtitlePageHeader, SubtitleSectionHeader } from './SubtitleUi';

/**
 * One responsibility: align subtitle timing with the audio.
 * Audio keeps playing behind this screen, so the user can nudge while listening.
 */
@ComponentV2
export struct SubtitleSyncPage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};

  @Builder
  nudgeButton(label: string, deltaMs: number) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .backgroundColor('#14161D')
      .border({ width: 0.7, color: '#1FFFFFFF' })
      .borderRadius(10)
      .onClick(() => this.session.nudgeDelay(deltaMs))
  }

  build() {
    Column() {
      SubtitlePageHeader({
        title: '时间轴同步',
        caption: '仅对外挂字幕生效，音频继续播放',
        onBack: () => this.onBack(),
        onClose: () => this.onClose()
      })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 10 }) {
            SubtitleSectionHeader({
              title: '当前字幕',
              note: '播放到下一句时更新'
            })
            Text(this.session.currentCueText ? this.session.currentCueText : '当前没有正在显示的字幕')
              .fontSize(15)
              .lineHeight(22)
              .fontColor(this.session.currentCueText ? Color.White : '#6B7280')
              .width('100%')
              .padding(14)
              .borderRadius(10)
              .backgroundColor('#101218')
              .constraintSize({ minHeight: 64 })
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Text('当前延迟')
              .fontSize(12)
              .fontColor('#9CA3AF')
            Text(this.session.delayLabel())
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.session.delayMs === 0 ? '#F8FAFC' : '#60A5FA')
            Text(this.session.delayMs === 0
              ? '字幕与音轨完全对齐'
              : (this.session.delayMs > 0 ? '字幕向后推迟显示' : '字幕提前显示'))
              .fontSize(11)
              .fontColor('#6B7280')
          }
          .width('100%')
          .padding(18)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Center)

          Column({ space: 10 }) {
            SubtitleSectionHeader({ title: '微调', note: '0.1 秒微调；0.5 秒快速对齐' })
            Row({ space: 8 }) {
              this.nudgeButton('-1.0s', -1000)
              this.nudgeButton('-0.5s', -500)
              this.nudgeButton('-0.1s', -100)
            }
            .width('100%')
            Row({ space: 8 }) {
              this.nudgeButton('+0.1s', 100)
              this.nudgeButton('+0.5s', 500)
              this.nudgeButton('+1.0s', 1000)
            }
            .width('100%')
            Button('归零')
              .width('100%')
              .height(38)
              .fontSize(13)
              .fontColor(this.session.delayMs === 0 ? '#6B7280' : '#93C5FD')
              .backgroundColor('#1A3B82F6')
              .borderRadius(10)
              .enabled(this.session.delayMs !== 0)
              .onClick(() => this.session.setDelayMs(0))
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

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

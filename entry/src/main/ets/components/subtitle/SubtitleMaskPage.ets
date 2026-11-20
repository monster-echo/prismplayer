import { SubtitleSession } from '../../services/SubtitleSession';
import {
  SubtitlePageHeader,
  SubtitleSectionHeader,
  SubtitleToast,
  SubtitleToggleRow
} from './SubtitleUi';

/**
 * One responsibility: the English-learning occlusion band that covers burned-in subtitles.
 * Manual adjustment needs the real video, so that action returns to the player and lets the
 * player own the drag interaction.
 */
@ComponentV2
export struct SubtitleMaskPage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};
  @Param onManualAdjust: () => void = () => {};

  private readonly previewHeight: number = 168;

  private bandTop(): number {
    return this.session.maskYTop * this.previewHeight;
  }

  private bandHeight(): number {
    const raw = (this.session.maskYBottom - this.session.maskYTop) * this.previewHeight;
    return raw > 6 ? raw : 6;
  }

  private async detect(): Promise<void> {
    try {
      const ok = await this.session.detectBurnedInSubtitle();
      SubtitleToast.show(this.getUIContext(), ok ? '已识别并应用遮挡区域' : '未检测到内嵌字幕，可手动调整');
    } catch (_e) {
      SubtitleToast.show(this.getUIContext(), '识别失败，请手动调整遮挡范围');
    }
  }

  private saveAsDefault(): void {
    this.session.saveMaskAsDefault();
    SubtitleToast.show(this.getUIContext(), this.session.maskEnabled ? '已设为新视频默认开启' : '已设为新视频默认关闭');
  }

  build() {
    Column() {
      SubtitlePageHeader({
        title: '内嵌字幕遮挡',
        caption: '盖住画面硬字幕，长按可临时露出',
        onBack: () => this.onBack(),
        onClose: () => this.onClose()
      })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 10 }) {
            SubtitleSectionHeader({
              title: '遮挡范围预览',
              note: '按画面比例保存'
            })
            Stack({ alignContent: Alignment.TopStart }) {
              Column()
                .width('100%')
                .height(this.previewHeight)
                .linearGradient({ angle: 135, colors: [['#24344D', 0], ['#0B1220', 0.7], ['#070A10', 1]] })

              Text('画面区域')
                .fontSize(10)
                .fontColor('#64748B')
                .position({ x: 10, y: 8 })

              Column()
                .width('100%')
                .height(this.bandHeight())
                .position({ x: 0, y: this.bandTop() })
                .backgroundColor('#FF000000')
                .border({ width: 1, color: '#553B82F6' })

              Text('字幕遮挡黑条')
                .fontSize(9)
                .fontColor('#94A3B8')
                .position({ x: 10, y: Math.min(this.previewHeight - 18, Math.max(6, this.bandTop() + 5)) })
            }
            .width('100%')
            .height(this.previewHeight)
            .borderRadius(10)
            .clip(true)
            .border({ width: 0.7, color: '#1FFFFFFF' })

            Row() {
              Text('当前范围').fontSize(11).fontColor('#6B7280')
              Blank()
              Text(this.session.maskRangeLabel()).fontSize(11).fontColor('#93C5FD')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 14 }) {
            SubtitleToggleRow({
              title: '遮挡内嵌字幕',
              desc: '关闭后立即隐藏，长按可临时露出',
              value: this.session.maskEnabled,
              onChange: (v: boolean) => this.session.setMaskEnabled(v)
            })

            Divider().color('#1FFFFFFF')

            Row({ space: 8 }) {
              Button(this.session.detectingMask ? '识别中...' : '自动识别字幕区域')
                .layoutWeight(1)
                .height(40)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.session.canDetectBurnedInSubtitle() && !this.session.detectingMask ? Color.White : '#6B7280')
                .backgroundColor(this.session.canDetectBurnedInSubtitle() ? '#3B82F6' : '#101218')
                .borderRadius(10)
                .enabled(this.session.canDetectBurnedInSubtitle() && !this.session.detectingMask)
                .onClick(() => this.detect())

              Button('手动调整')
                .layoutWeight(1)
                .height(40)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .backgroundColor('#1A3B82F6')
                .border({ width: 0.7, color: '#333B82F6' })
                .borderRadius(10)
                .onClick(() => this.onManualAdjust())
            }
            .width('100%')

            if (!this.session.canDetectBurnedInSubtitle()) {
              Text('远程视频请手动调整。')
                .fontSize(10)
                .lineHeight(15)
                .fontColor('#6B7280')
            }

            Text('回到画面拖动上下边缘，点「完成」保存。')
              .fontSize(10)
              .lineHeight(16)
              .fontColor('#6B7280')
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            SubtitleSectionHeader({
              title: '默认行为',
              note: '按视频记忆，可设为新视频默认'
            })
            Button('设为新视频默认')
              .width('100%')
              .height(38)
              .fontSize(12)
              .fontColor('#93C5FD')
              .backgroundColor('#1A3B82F6')
              .borderRadius(9)
              .onClick(() => this.saveAsDefault())
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

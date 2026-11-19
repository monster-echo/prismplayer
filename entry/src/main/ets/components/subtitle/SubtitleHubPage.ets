import { SubtitlePageRoute } from '../../common/Types';
import { SubtitleSession } from '../../services/SubtitleSession';
import { SubtitleNavRow, SubtitlePageHeader, SubtitleToggleRow } from './SubtitleUi';

/**
 * Subtitle hub: an index of single-purpose subtitle screens.
 * Deliberately contains no feature controls beyond the master visibility switch.
 */
@ComponentV2
export struct SubtitleHubPage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Param onNavigate: (route: SubtitlePageRoute) => void = (_route: SubtitlePageRoute) => {};
  @Param onClose: () => void = () => {};

  private mediaCaption(): string {
    const item = this.session.mediaItem;
    if (!item) return '当前没有播放中的视频';
    const quality = item.qualityTag ? ` · ${item.qualityTag}` : '';
    return `当前视频：${item.title}${quality}`;
  }

  private trackSummary(): string {
    if (!this.session.active) return '';
    const enabled = this.session.enabledTrackIds.length;
    const total = this.session.externalTracks.length;
    const embedded = this.session.selectedEmbeddedTrack >= 0 ? '内嵌已选' : '内嵌关';
    return `${enabled}/${total} 外挂 · ${embedded}`;
  }

  private styleSummary(): string {
    const bg = this.session.bgEnabled ? `底框 ${this.session.bgOpacityPercent}%` : '无底框';
    return `${this.session.fontFp} fp · ${bg}`;
  }

  private onlineSummary(): string {
    const count = this.session.onlineResults.length;
    const lang = this.session.languageFilter === 'all' ? '' : `${this.session.languageFilterLabel()} · `;
    return count > 0 ? `${lang}${count} 条候选` : `${lang}自动匹配 / 搜索`;
  }

  private assistSummary(): string {
    const t = this.session.translateEnabled ? '开' : '关';
    const s = this.session.ttsEnabled ? '开' : '关';
    return `翻译${t} · 朗读${s}`;
  }

  @Builder
  navDivider() {
    Divider().color('#1FFFFFFF').margin({ left: 60 })
  }

  build() {
    Column() {
      SubtitlePageHeader({
        title: '字幕',
        caption: this.mediaCaption(),
        showBack: false,
        onClose: () => this.onClose()
      })

      if (!this.session.active) {
        Column({ space: 8 }) {
          Text('当前没有可用的字幕会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E5E7EB')
          Text('请先从播放页进入字幕中心。').fontSize(12).fontColor('#9CA3AF')
        }
        .width('100%')
        .padding(24)
        .borderRadius(14)
        .backgroundColor('#14161D')
        .margin({ left: 18, right: 18, top: 8 })
        .alignItems(HorizontalAlign.Start)
      } else {
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              SubtitleToggleRow({
                title: '显示字幕',
                desc: `已启用 ${this.session.enabledTrackIds.length} 条外挂字幕 · 内嵌字幕：${this.session.selectedEmbeddedLabel()}`,
                value: this.session.enabled,
                onChange: (v: boolean) => this.session.setEnabled(v)
              })
              Divider().color('#1FFFFFFF')
              Text('每个功能独立成一页；从播放器打开的字幕面板只负责当前这一部视频。')
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

            Column() {
              SubtitleNavRow({
                badge: '轨',
                title: '字幕轨道',
                value: this.trackSummary(),
                onTap: () => this.onNavigate('tracks')
              })
              this.navDivider()
              SubtitleNavRow({
                badge: '样',
                title: '字幕样式',
                value: this.styleSummary(),
                onTap: () => this.onNavigate('style')
              })
              this.navDivider()
              SubtitleNavRow({
                badge: '同',
                title: '时间轴同步',
                value: this.session.delayLabel(),
                onTap: () => this.onNavigate('sync')
              })
              this.navDivider()
              SubtitleNavRow({
                badge: '网',
                title: '在线字幕',
                value: this.onlineSummary(),
                onTap: () => this.onNavigate('online')
              })
              this.navDivider()
              SubtitleNavRow({
                badge: '译',
                title: '翻译与朗读',
                value: this.assistSummary(),
                onTap: () => this.onNavigate('assist')
              })
              this.navDivider()
              SubtitleNavRow({
                badge: '遮',
                title: '内嵌字幕遮挡',
                value: this.session.maskEnabled ? '已开启' : '已关闭',
                onTap: () => this.onNavigate('mask')
              })
            }
            .width('100%')
            .borderRadius(14)
            .backgroundColor('#14161D')
            .border({ width: 0.7, color: '#1FFFFFFF' })

            Text('内嵌字幕遮挡属于「英语学习模式」：用黑条盖住画面里烧录的硬字幕，长按画面可临时露出。')
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF0B0D12')
  }
}

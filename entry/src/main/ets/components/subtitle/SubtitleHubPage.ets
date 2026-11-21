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
    return `${item.title}${quality}`;
  }

  private trackSummary(): string {
    if (!this.session.active) return '';
    const enabled = this.session.enabledTrackIds.length;
    const total = this.session.externalTracks.length;
    const embedded = this.session.selectedEmbeddedTrack >= 0 ? '内嵌已选' : '内嵌关';
    return `外挂 ${enabled}/${total} · ${embedded}`;
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
        Text('请从播放页打开字幕')
          .fontSize(13)
          .fontColor('#9CA3AF')
          .width('100%')
          .padding(24)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .margin({ left: 18, right: 18, top: 8 })
      } else {
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              SubtitleToggleRow({
                title: '显示字幕',
                value: this.session.enabled,
                onChange: (v: boolean) => this.session.setEnabled(v)
              })
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

          }
          .padding({ left: 18, right: 18, top: 8, bottom: 36 })
          .width('100%')
        }.edgeEffect(EdgeEffect.Spring)
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

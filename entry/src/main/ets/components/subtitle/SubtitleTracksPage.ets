import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { ExternalSubtitleTrack, PlayerTrackItem } from '../../common/Types';
import { SubtitleEngine } from '../../services/SubtitleEngine';
import { SubtitleService } from '../../services/SubtitleService';
import { SubtitleSession } from '../../services/SubtitleSession';
import {
  SubtitleChip,
  SubtitlePageHeader,
  SubtitleSectionHeader,
  SubtitleToast,
  SubtitleToggleRow
} from './SubtitleUi';

/**
 * One responsibility: decide which subtitle tracks are active.
 * Embedded tracks, sidecar tracks, local imports and bilingual line filtering live together
 * because they all answer the same question: "what text is on screen?".
 */
@ComponentV2
export struct SubtitleTracksPage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};

  private selectEmbedded(index: number): void {
    if (!this.session.selectEmbeddedTrack(index)) {
      SubtitleToast.show(this.getUIContext(), '切换内嵌字幕轨失败，请确认当前为硬解内核');
    }
  }

  private clearEmbedded(): void {
    this.session.clearEmbeddedTrack();
    SubtitleToast.show(this.getUIContext(), '已关闭内嵌字幕');
  }

  private toggleExternal(track: ExternalSubtitleTrack): void {
    this.session.toggleTrackEnabled(track.id);
  }

  private removeExternal(track: ExternalSubtitleTrack): void {
    this.session.removeExternalTrack(track.id);
    SubtitleToast.show(this.getUIContext(), `已移除 ${track.label}`);
  }

  private async importLocal(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const docPicker = new picker.DocumentViewPicker(ctx);
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 8;
      const uris = await docPicker.select(opts);
      if (!uris || uris.length === 0) return;

      let loaded = 0;
      let lastName = '';
      for (let i = 0; i < uris.length; i++) {
        try {
          const file = fs.openSync(uris[i], fs.OpenMode.READ_ONLY);
          const stat = fs.statSync(file.fd);
          const buf = new ArrayBuffer(Math.min(stat.size, 8 * 1024 * 1024));
          fs.readSync(file.fd, buf);
          fs.closeSync(file.fd);

          const text = SubtitleService.decodeSubtitleBytes(buf);
          const decoded = decodeURIComponent(uris[i]);
          const name = decoded.substring(decoded.lastIndexOf('/') + 1);
          this.session.addExternalTrack(SubtitleEngine.parse(text, name, uris[i]), loaded === 0);
          lastName = name;
          loaded++;
        } catch (_e) {
          // Skip unreadable files and continue importing the rest.
        }
      }
      if (loaded > 0) {
        this.session.setEnabled(true);
        SubtitleToast.show(this.getUIContext(), loaded > 1 ? `已加载 ${loaded} 条字幕轨道` : `已加载字幕：${lastName}`);
      } else {
        SubtitleToast.show(this.getUIContext(), '加载字幕文件失败');
      }
    } catch (_e) {
      SubtitleToast.show(this.getUIContext(), '加载字幕文件失败');
    }
  }

  @Builder
  sectionCardTitle(title: string, note: string) {
    SubtitleSectionHeader({ title: title, note: note })
  }

  @Builder
  embeddedRow(track: PlayerTrackItem) {
    Row({ space: 10 }) {
      SymbolGlyph(this.session.selectedEmbeddedTrack === track.index
        ? $r('sys.symbol.checkmark_circle_fill')
        : $r('sys.symbol.circle'))
        .fontSize(17)
        .fontColor([this.session.selectedEmbeddedTrack === track.index ? '#3B82F6' : '#6B7280'])
      Column({ space: 2 }) {
        Text(track.label)
          .fontSize(13)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (track.codec) {
          Text(track.codec).fontSize(10).fontColor('#6B7280')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor('#101218')
    .onClick(() => this.selectEmbedded(track.index))
  }

  @Builder
  externalRow(track: ExternalSubtitleTrack) {
    Row({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.session.isTrackEnabled(track.id)
          ? $r('sys.symbol.checkmark_circle_fill')
          : $r('sys.symbol.circle'))
          .fontSize(17)
          .fontColor([this.session.isTrackEnabled(track.id) ? '#3B82F6' : '#6B7280'])
        Column({ space: 2 }) {
          Text(track.label)
            .fontSize(13)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${track.format.toUpperCase()} · ${track.cues.length} 条`)
            .fontSize(10)
            .fontColor('#6B7280')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.session.langBadge(track.langTag))
          .fontSize(9)
          .fontColor('#94A3B8')
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(4)
          .backgroundColor('#1A38BDF8')
      }
      .alignItems(VerticalAlign.Center)
      .layoutWeight(1)
      .onClick(() => this.toggleExternal(track))

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(13)
        .fontColor(['#6B7280'])
        .padding(8)
        .onClick(() => this.removeExternal(track))
    }
    .width('100%')
    .padding({ left: 10, right: 4, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor('#101218')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      SubtitlePageHeader({
        title: '字幕轨道',
        caption: '只影响当前视频',
        onBack: () => this.onBack(),
        onClose: () => this.onClose()
      })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 10 }) {
            SubtitleToggleRow({
              title: '显示字幕',
              desc: '同时关闭内嵌与外挂',
              value: this.session.enabled,
              onChange: (v: boolean) => this.session.setEnabled(v)
            })
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })

          Column({ space: 10 }) {
            this.sectionCardTitle(
              `内嵌字幕轨（${this.session.embeddedTracks.length}）`,
              this.session.embeddedSupported
                ? '容器内字幕流，可与外挂同时显示'
                : '当前为 FFmpeg 软解内核，内嵌字幕轨只能在硬解内核下选择'
            )
            if (this.session.embeddedSupported) {
              if (this.session.embeddedTracks.length === 0) {
                Text('当前视频没有检测到内嵌字幕轨').fontSize(12).fontColor('#6B7280')
              } else {
                Row({ space: 8 }) {
                  SubtitleChip({
                    label: '关闭内嵌字幕',
                    active: this.session.selectedEmbeddedTrack < 0,
                    onTap: () => this.clearEmbedded()
                  })
                }
                .width('100%')
                ForEach(this.session.embeddedTracks, (track: PlayerTrackItem) => {
                  this.embeddedRow(track)
                }, (track: PlayerTrackItem) => `emb_${track.index}_${this.session.selectedEmbeddedTrack === track.index}`)
              }
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            this.sectionCardTitle(
              `外挂字幕轨（${this.session.externalTracks.length}）`,
              '可多选，用于双语或特效叠加'
            )
            if (this.session.externalTracks.length === 0) {
              Text('尚未挂载外挂字幕').fontSize(12).fontColor('#6B7280')
            } else {
              ForEach(this.session.externalTracks, (track: ExternalSubtitleTrack) => {
                this.externalRow(track)
              }, (track: ExternalSubtitleTrack) => `ext_${track.id}_${this.session.isTrackEnabled(track.id)}`)
              Text(this.session.enabledTrackIds.length > 0
                ? `已启用 ${this.session.enabledTrackIds.length} 条轨道`
                : '全部轨道已停用，勾选行以启用')
                .fontSize(10)
                .fontColor(this.session.enabledTrackIds.length > 0 ? '#10B981' : '#6B7280')
            }

            Button('导入本地字幕')
              .width('100%')
              .height(40)
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor('#3B82F6')
              .borderRadius(10)
              .onClick(() => this.importLocal())
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Text('内嵌与外挂可同时显示；重叠时关掉一条。')
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

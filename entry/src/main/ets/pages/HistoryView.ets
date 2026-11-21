import { BreakpointType } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { Layout } from '../common/Layout';
import { MediaArtwork } from '../common/MediaArtwork';
import { appMenuOptions } from '../common/MenuSurface';
import { MediaItem, WatchHistoryRecord } from '../common/Types';
import { AppStore } from '../services/AppStore';

@ComponentV2
export struct HistoryView {
  @Param breakpoint: BreakpointType = 'sm';
  @Param onPlayItem: (item: MediaItem, startPosMs: number) => void = () => {};
  @Param onOpenDetail: (item: MediaItem) => void = () => {};
  @Local store: AppStore = AppStore.getInstance();
  @Local refreshing: boolean = false;

  private resolveItem(rec: WatchHistoryRecord): MediaItem {
    const matched = this.store.mediaItems.find(m => m.id === rec.itemId);
    if (matched) return matched;
    return {
      id: rec.itemId,
      sourceId: rec.sourceId,
      sourceType: rec.streamUrl.startsWith('http') ? 'webdav' : 'local',
      remotePath: rec.streamUrl,
      streamUrl: rec.streamUrl,
      fileName: rec.title,
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: rec.itemId,
      seriesTitle: rec.title,
      seasonNo: 1,
      episodeNo: 0,
      title: rec.title,
      originalTitle: '',
      year: 0,
      overview: '',
      posterUrl: rec.posterUrl,
      backdropUrl: rec.posterUrl,
      rating: 0,
      qualityTag: '',
      tmdbId: 0,
      durationMs: rec.durationMs,
      subtitleUrl: '',
      addedAt: rec.updatedAt
    };
  }

  private confirmClearAll(): void {
    this.getUIContext().showAlertDialog({
      title: '清空观看记录',
      message: '确定要删除所有续播进度记录吗？该操作不会删除网盘或本地视频文件。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认清空',
        fontColor: $r('app.color.danger'),
        action: () => { this.store.clearWatchHistory(); }
      }
    });
  }

  /** 大屏一条记录给足宽度后并排两条，避免一张卡片横跨整屏。 */
  private gridTemplate(): string {
    return this.breakpoint === 'xl' && this.store.getVisibleWatchHistory().length > 1 ? '1fr 1fr' : '1fr';
  }

  build() {
    Row() {
      Column({ space: 16 }) {
        Row() {
          Column({ space: 3 }) {
            Text('最近观看')
              .fontSize(this.breakpoint === 'sm' ? 26 : 28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(`共 ${this.store.getVisibleWatchHistory().length} 条续播记录`)
              .fontSize(12)
              .fontColor($r('app.color.text_body_muted'))
          }.alignItems(HorizontalAlign.Start)

          Blank()

          if (this.store.getVisibleWatchHistory().length > 0) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(16)
                .fontColor([$r('app.color.danger')])
            }
            .width(38)
            .height(38)
            .backgroundColor('#1AF87171')
            .onClick(() => this.confirmClearAll())
          }
        }
        .width('100%')

        Refresh({ refreshing: this.refreshing }) {
        Column() {
        if (this.store.getVisibleWatchHistory().length === 0) {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise_clock'))
              .fontSize(40)
              .fontColor([$r('app.color.text_muted')])
            Text('暂无观看历史')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('播放任意本地、SMB、Plex 或 WebDAV 视频后，这里会自动保存续播断点')
              .fontSize(13)
              .fontColor($r('app.color.text_body_muted'))
          }
          .width('100%')
          .padding({ top: 64 })
        } else {
          Scroll() {
            Grid() {
              ForEach(this.store.getVisibleWatchHistory(), (rec: WatchHistoryRecord) => {
                GridItem() {
                  Row({ space: 14 }) {
                    if (rec.posterUrl) {
                      Image(MediaArtwork.resolve(rec.posterUrl))
                        .width(98)
                        .height(62)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(10)
                    } else {
                      Column() {
                        Image($r('app.media.ic_file_video'))
                          .width(26)
                          .height(26)
                      }
                      .width(98)
                      .height(62)
                      .justifyContent(FlexAlign.Center)
                      .linearGradient({
                        angle: 145,
                        colors: [
                          [MediaArtwork.paletteFor(rec.title).top, 0],
                          [MediaArtwork.paletteFor(rec.title).bottom, 1]
                        ]
                      })
                      .borderRadius(10)
                      .border({ width: 0.6, color: $r('app.color.fill_strong') })
                    }

                    Column({ space: 5 }) {
                      Text(rec.title)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Text(
                        `${rec.finished ? '已看完' : '已看至 ' + Formatters.formatDuration(rec.positionMs)}` +
                        `${rec.durationMs > 0 ? ' / ' + Formatters.formatDuration(rec.durationMs) : ''}` +
                        ` · ${Formatters.formatRelativeTime(rec.updatedAt)}`
                      )
                        .fontSize(12)
                        .fontColor($r('app.color.text_body_muted'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Row() {
                        Row()
                          .width(`${rec.durationMs > 0 ? Math.min(100, Math.round((rec.positionMs / rec.durationMs) * 100)) : 20}%`)
                          .height(3)
                          .backgroundColor(rec.finished ? $r('app.color.success') : $r('app.color.accent_blue'))
                      }
                      .width('100%')
                      .height(3)
                      .backgroundColor($r('app.color.bg_secondary'))
                      .borderRadius(2)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.play_fill')).fontSize(13).fontColor([Color.White])
                    }
                    .width(36)
                    .height(36)
                    .backgroundColor($r('app.color.accent_blue'))
                    .onClick(() => {
                      const target = this.resolveItem(rec);
                      this.onPlayItem(target, rec.finished ? 0 : rec.positionMs);
                    })

                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                        .fontSize(17)
                        .fontColor([$r('app.color.text_secondary')])
                    }
                    .width(32)
                    .height(32)
                    .backgroundColor(Color.Transparent)
                    .bindMenu([
                      {
                        value: '影片详情',
                        action: () => this.onOpenDetail(this.resolveItem(rec))
                      },
                      {
                        value: '从头播放',
                        action: () => this.onPlayItem(this.resolveItem(rec), 0)
                      },
                      {
                        value: '移除此记录',
                        action: () => { this.store.deleteWatchHistoryItem(rec.itemId); }
                      }
                    ], appMenuOptions())
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.bg_elevated'))
                  .border({ width: 0.8, color: $r('app.color.fill_strong') })
                  .onClick(() => this.onOpenDetail(this.resolveItem(rec)))
                }
              }, (rec: WatchHistoryRecord) => rec.itemId)
            }
            .columnsTemplate(this.gridTemplate())
            .columnsGap(12)
            .rowsGap(12)
            .width('100%')
          }.edgeEffect(EdgeEffect.Spring)
          .height('100%')
          .width('100%')
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)
        }
        }
        .width('100%')
        .height('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(async () => {
          this.refreshing = true;
          await this.store.reloadAllData();
          this.refreshing = false;
        })
      }
      .padding({
        left: Layout.gutter(this.breakpoint),
        right: Layout.gutter(this.breakpoint),
        top: 20,
        bottom: 20
      })
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: Layout.listMax(this.breakpoint) + Layout.gutter(this.breakpoint) * 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_primary'))
  }
}

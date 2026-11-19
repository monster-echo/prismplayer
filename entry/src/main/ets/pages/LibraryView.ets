import { BreakpointType } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { MediaArtwork } from '../common/MediaArtwork';
import { MediaCategory, MediaItem, SeriesGroup, WatchHistoryRecord } from '../common/Types';
import { PosterCard } from '../components/PosterCard';
import { AppStore } from '../services/AppStore';

@ComponentV2
export struct LibraryView {
  @Param breakpoint: BreakpointType = 'sm';
  @Param onOpenMovie: (item: MediaItem) => void = () => {};
  @Param onOpenSeries: (series: SeriesGroup) => void = () => {};
  @Param onPlayDirect: (item: MediaItem, startPosMs: number) => void = () => {};
  @Param onGoSources: () => void = () => {};
  @Param onOpenSearch: () => void = () => {};
  @Param onOpenVault: () => void = () => {};

  @Local store: AppStore = AppStore.getInstance();
  @Local category: MediaCategory = 'all';
  @Local heroImgFailed: boolean = false;

  private getGridTemplate(): string {
    if (this.breakpoint === 'xl') return '1fr 1fr 1fr 1fr 1fr 1fr';
    if (this.breakpoint === 'lg') return '1fr 1fr 1fr 1fr 1fr';
    if (this.breakpoint === 'md' || this.store.isLandscape) return '1fr 1fr 1fr 1fr';
    return '1fr 1fr 1fr';
  }

  private getFilteredMovies(): MediaItem[] {
    if (this.category === 'tv') return [];
    if (this.category === 'favorite') {
      return this.store.getFavoriteMediaItems();
    }
    if (this.category === 'private') {
      return this.store.getHiddenMediaItems();
    }
    return this.store.getVisibleMediaItems().filter(it => it.mediaType === 'movie');
  }

  private getFilteredSeries(): SeriesGroup[] {
    if (this.category === 'movie' || this.category === 'favorite' || this.category === 'private') return [];
    return this.store.getSeriesGroups();
  }

  private getContinueWatching(): WatchHistoryRecord[] {
    return this.store.getVisibleWatchHistory().filter(h => !h.finished && h.positionMs > 2000).slice(0, 10);
  }

  private getHeroItem(): MediaItem | null {
    const visible = this.store.getVisibleMediaItems();
    if (visible.length === 0) return null;
    const recent = this.getContinueWatching();
    if (recent.length > 0) {
      const found = visible.find(m => m.id === recent[0].itemId);
      if (found) return found;
    }
    return visible[0];
  }

  private getProgressRatio(itemId: string): number {
    const h = this.store.getHistoryForItem(itemId);
    if (!h || h.durationMs <= 0) return 0;
    return Math.min(1, h.positionMs / h.durationMs);
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        // Sleek Cinema Header + Icon Search & Import
        Row({ space: 10 }) {
          Row({ space: 10 }) {
            if (this.breakpoint === 'sm') {
              Image($r('app.media.ic_brand_prism'))
                .width(34)
                .height(34)
                .borderRadius(9)
            }
            Column({ space: 2 }) {
              Text('媒体影库')
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text(
                this.store.isScanning
                  ? this.store.scanStatusText
                  : `${this.getFilteredMovies().length} 部电影 · ${this.getFilteredSeries().length} 部剧集`
              )
                .fontSize(12)
                .fontColor(this.store.isScanning ? $r('app.color.accent_blue') : $r('app.color.text_muted'))
            }.alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(38)
          .height(38)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.fill_strong') })
          .onClick(() => this.onOpenSearch())

          Button() {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(14)
                .fontColor([Color.White])
              Text('导入')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
          }
          .height(38)
          .padding({ left: 13, right: 14 })
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(12)
          .shadow({ radius: 10, color: '#4D5E8BFF', offsetX: 0, offsetY: 3 })
          .onClick(() => {
            this.store.importLocalVideos();
          })
        }
        .width('100%')

        // Hero Cinema Spotlight Banner
        if (this.getHeroItem() !== null) {
          Stack({ alignContent: Alignment.BottomStart }) {
            if ((this.getHeroItem()!.backdropUrl || this.getHeroItem()!.posterUrl) && !this.heroImgFailed) {
              Image(MediaArtwork.resolve(this.getHeroItem()!.backdropUrl || this.getHeroItem()!.posterUrl))
                .width('100%')
                .height(this.breakpoint === 'sm' ? 224 : 280)
                .objectFit(ImageFit.Cover)
                .borderRadius(18)
                .onError(() => {
                  this.heroImgFailed = true;
                })
            } else {
              Stack({ alignContent: Alignment.TopEnd }) {
                Column()
                  .width('100%')
                  .height(this.breakpoint === 'sm' ? 224 : 280)
                  .linearGradient({
                    angle: 135,
                    colors: [
                      [MediaArtwork.paletteFor(this.getHeroItem()!.title).top, 0],
                      [MediaArtwork.paletteFor(this.getHeroItem()!.title).bottom, 1]
                    ]
                  })
                  .borderRadius(18)
                Image($r('app.media.art_cinema_motif'))
                  .width(260)
                  .height(150)
                  .objectFit(ImageFit.Contain)
                  .margin({ top: 12, right: 8 })
              }
              .width('100%')
              .height(this.breakpoint === 'sm' ? 224 : 280)
              .borderRadius(18)
            }

            Column()
              .width('100%')
              .height(this.breakpoint === 'sm' ? 224 : 280)
              .linearGradient({
                angle: 180,
                colors: [['#1A0A0B0F', 0], ['#880A0B0F', 0.45], ['#F00A0B0F', 1]]
              })
              .borderRadius(18)

            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text('影库精选')
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(6)
                  .backgroundColor($r('app.color.accent_blue'))
                if (this.getHeroItem()!.qualityTag) {
                  Text(this.getHeroItem()!.qualityTag)
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.accent_cyan'))
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(6)
                    .backgroundColor('#800A0B0F')
                    .border({ width: 0.5, color: '#4438BDF8' })
                }
                if (this.getHeroItem()!.rating > 0) {
                  Row({ space: 3 }) {
                    SymbolGlyph($r('sys.symbol.star_fill'))
                      .fontSize(10)
                      .fontColor([$r('app.color.accent_gold')])
                    Text(this.getHeroItem()!.rating.toFixed(1))
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.accent_gold'))
                  }
                  .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                  .borderRadius(6)
                  .backgroundColor('#800A0B0F')
                }
              }

              Text(this.getHeroItem()!.title)
                .fontSize(this.breakpoint === 'sm' ? 21 : 28)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textShadow({ radius: 8, color: '#CC000000', offsetX: 0, offsetY: 2 })

              Text(
                this.getHeroItem()!.overview ||
                `${this.getHeroItem()!.qualityTag || '高清电影'} · WebDAV / NAS 原盘直连${this.getHeroItem()!.fileSize > 0 ? ' · ' + Formatters.formatBytes(this.getHeroItem()!.fileSize) : ''}`
              )
                .fontSize(12)
                .lineHeight(18)
                .fontColor('#D9EEF2FA')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 560 })

              Row({ space: 10 }) {
                Button() {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.play_fill'))
                      .fontSize(13)
                      .fontColor([Color.White])
                    Text('立即播放')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                  }
                }
                .height(38)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.accent_blue'))
                .borderRadius(10)
                .shadow({ radius: 12, color: '#665E8BFF', offsetX: 0, offsetY: 4 })
                .onClick(() => {
                  const hero = this.getHeroItem()!;
                  const hist = this.store.getHistoryForItem(hero.id);
                  this.onPlayDirect(hero, hist && !hist.finished ? hist.positionMs : 0);
                })

                Button('影片详情')
                  .height(38)
                  .padding({ left: 14, right: 14 })
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor('#80191D2A')
                  .borderRadius(10)
                  .border({ width: 0.8, color: $r('app.color.fill_strong') })
                  .onClick(() => {
                    this.onOpenMovie(this.getHeroItem()!);
                  })
              }
              .padding({ top: 4 })
            }
            .padding(20)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .borderRadius(18)
          .border({ width: 1, color: $r('app.color.fill_strong') })
          .shadow({ radius: 18, color: '#80000000', offsetX: 0, offsetY: 8 })
        }

        // Continue Watching Rail
        if (this.getContinueWatching().length > 0) {
          Column({ space: 10 }) {
            Text('继续观看')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.getContinueWatching(), (rec: WatchHistoryRecord) => {
                  Column({ space: 6 }) {
                    Stack({ alignContent: Alignment.Bottom }) {
                      if (rec.posterUrl) {
                        Image(MediaArtwork.resolve(rec.posterUrl))
                          .width(216)
                          .height(122)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(12)
                      } else {
                        Column() {
                          SymbolGlyph($r('sys.symbol.play_circle_fill'))
                            .fontSize(32)
                            .fontColor([MediaArtwork.paletteFor(rec.title).accent])
                        }
                        .width(216)
                        .height(122)
                        .justifyContent(FlexAlign.Center)
                        .linearGradient({
                          angle: 145,
                          colors: [
                            [MediaArtwork.paletteFor(rec.title).top, 0],
                            [MediaArtwork.paletteFor(rec.title).bottom, 1]
                          ]
                        })
                        .borderRadius(12)
                      }

                      Column()
                        .width(216)
                        .height(122)
                        .linearGradient({
                          angle: 180,
                          colors: [['#00000000', 0.4], ['#CC0A0B0F', 1]]
                        })
                        .borderRadius(12)

                      Column({ space: 5 }) {
                        Text(`续播 ${Formatters.formatDuration(rec.positionMs)}`)
                          .fontSize(10)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(Color.White)
                          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                          .borderRadius(5)
                          .backgroundColor('#B3000000')
                          .alignSelf(ItemAlign.Start)

                        Row() {
                          Row()
                            .width(`${rec.durationMs > 0 ? Math.min(100, Math.max(5, Math.round((rec.positionMs / rec.durationMs) * 100))) : 15}%`)
                            .height(3)
                            .backgroundColor($r('app.color.accent_blue'))
                        }
                        .width('100%')
                        .height(3)
                        .backgroundColor('#66FFFFFF')
                        .borderRadius(2)
                      }
                      .width(216)
                      .padding(8)
                    }
                    .width(216)
                    .height(122)
                    .borderRadius(12)
                    .border({ width: 0.8, color: $r('app.color.fill_strong') })

                    Text(rec.title)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(216)
                  }
                  .onClick(() => {
                    const matched = this.store.mediaItems.find(m => m.id === rec.itemId);
                    if (matched) {
                      this.onPlayDirect(matched, rec.positionMs);
                    }
                  })
                }, (rec: WatchHistoryRecord) => rec.itemId)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // Category Filter Chips + Secondary More Menu
        Row({ space: 8 }) {
          this.filterChip('全部', 'all')
          this.filterChip('电影', 'movie')
          this.filterChip('剧集', 'tv')
          this.filterChip('收藏', 'favorite')
          if (this.store.vaultUnlocked) {
            this.filterChip('私密', 'private')
          }
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(34)
          .height(34)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.fill_strong') })
          .bindMenu([
            {
              value: '管理网络片源',
              action: () => this.onGoSources()
            },
            {
              value: '导入本地视频',
              action: () => { this.store.importLocalVideos(); }
            },
            {
              value: this.store.vaultUnlocked ? '锁定私密空间' : '私密文件夹解锁 / 管理',
              action: () => {
                if (this.store.vaultUnlocked) {
                  this.store.lockVault();
                } else {
                  this.onOpenVault();
                }
              }
            },
            {
              value: '恢复示例影库',
              action: () => { this.store.seedOpenShowcaseLibrary(); }
            }
          ])
        }
        .width('100%')

        // Series Section
        if (this.getFilteredSeries().length > 0) {
          Column({ space: 10 }) {
            Text('剧集')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Grid() {
              ForEach(this.getFilteredSeries(), (grp: SeriesGroup) => {
                GridItem() {
                  PosterCard({
                    title: grp.title,
                    subtitle: grp.year > 0 ? `${grp.year}` : `${grp.episodes.length} 集`,
                    posterUrl: grp.posterUrl,
                    rating: grp.rating,
                    episodeCountLabel: `${grp.episodes.length} 集`,
                    onSelect: () => this.onOpenSeries(grp)
                  })
                }
              }, (grp: SeriesGroup) => grp.seriesKey)
            }
            .columnsTemplate(this.getGridTemplate())
            .columnsGap(14)
            .rowsGap(16)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // Movies Section
        if (this.getFilteredMovies().length > 0) {
          Column({ space: 10 }) {
            Text('电影')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Grid() {
              ForEach(this.getFilteredMovies(), (item: MediaItem) => {
                GridItem() {
                  PosterCard({
                    title: item.title,
                    subtitle: item.year > 0 ? `${item.year}` : item.qualityTag,
                    posterUrl: item.posterUrl,
                    qualityTag: item.qualityTag,
                    rating: item.rating,
                    progressRatio: this.getProgressRatio(item.id),
                    onSelect: () => this.onOpenMovie(item)
                  })
                }
              }, (item: MediaItem) => item.id)
            }
            .columnsTemplate(this.getGridTemplate())
            .columnsGap(14)
            .rowsGap(16)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.getFilteredMovies().length === 0 && this.getFilteredSeries().length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.movie'))
              .fontSize(38)
              .fontColor([$r('app.color.text_muted')])
            Text('暂无匹配的影视内容')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('添加 WebDAV / Alist 网盘源自动刮削海报墙，或导入本地视频')
              .fontSize(13)
              .fontColor($r('app.color.text_muted'))
              .textAlign(TextAlign.Center)
            Row({ space: 10 }) {
              Button('添加 WebDAV / Alist')
                .height(38)
                .fontSize(13)
                .fontColor(Color.White)
                .backgroundColor($r('app.color.accent_blue'))
                .borderRadius(10)
                .onClick(() => this.onGoSources())
              Button('恢复演示影库')
                .height(38)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.bg_elevated'))
                .borderRadius(10)
                .onClick(() => {
                  this.store.seedOpenShowcaseLibrary();
                })
            }
          }
          .width('100%')
          .padding({ top: 48, bottom: 48 })
        }
      }
      .padding({ left: 20, right: 20, top: 16, bottom: 32 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .backgroundColor($r('app.color.bg_primary'))
    .scrollBar(BarState.Off)
  }

  @Builder
  filterChip(label: string, value: MediaCategory) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.category === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.category === value ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 15, right: 15, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.category === value ? $r('app.color.accent_blue') : $r('app.color.bg_elevated'))
      .border({ width: 0.8, color: this.category === value ? $r('app.color.accent_blue') : $r('app.color.fill_strong') })
      .onClick(() => {
        this.category = value;
      })
  }
}

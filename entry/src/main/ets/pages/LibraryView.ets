import { BreakpointType } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { Layout } from '../common/Layout';
import { MediaArtwork } from '../common/MediaArtwork';
import { appMenuOptions } from '../common/MenuSurface';
import { MediaCategory, MediaItem, MusicAlbum, SeriesGroup, WatchHistoryRecord } from '../common/Types';
import { MusicLibrary } from '../components/MusicLibrary';
import { PosterCard } from '../components/PosterCard';
import { AppStore } from '../services/AppStore';

@ComponentV2
export struct LibraryView {
  @Param breakpoint: BreakpointType = 'sm';
  @Param contentWidth: number = 360;
  @Param onOpenMovie: (item: MediaItem) => void = () => {};
  @Param onOpenSeries: (series: SeriesGroup) => void = () => {};
  @Param onPlayDirect: (item: MediaItem, startPosMs: number) => void = () => {};
  @Param onGoSources: () => void = () => {};
  @Param onOpenSearch: () => void = () => {};
  @Param onOpenVault: () => void = () => {};
  @Param onPlayAlbum: (album: MusicAlbum) => void = () => {};
  @Param onPlayMovieList: (items: MediaItem[]) => void = () => {};
  @Param onOpenMusicPlayer: () => void = () => {};

  @Local store: AppStore = AppStore.getInstance();
  @Local category: MediaCategory = 'all';
  @Local heroImgFailed: boolean = false;
  @Local refreshing: boolean = false;

  private getFilteredMovies(): MediaItem[] {
    if (this.category === 'tv' || this.category === 'music') return [];
    if (this.category === 'favorite') {
      return this.store.getFavoriteMediaItems().filter(it => it.mediaType !== 'track');
    }
    if (this.category === 'private') {
      return this.store.getHiddenMediaItems().filter(it => it.mediaType !== 'track');
    }
    return this.store.getVisibleMediaItems().filter(it => it.mediaType === 'movie');
  }

  private getFilteredSeries(): SeriesGroup[] {
    if (this.category === 'movie' || this.category === 'favorite' || this.category === 'private' || this.category === 'music') {
      return [];
    }
    return this.store.getSeriesGroups();
  }

  private musicAlbumCount(): number {
    return this.store.getMusicAlbums().length;
  }

  private musicTrackCount(): number {
    return this.store.getMusicTracks().length;
  }

  private getContinueWatching(): WatchHistoryRecord[] {
    return this.store.getVisibleWatchHistory().filter(h => !h.finished && h.positionMs > 2000).slice(0, 10);
  }

  private getHeroItem(): MediaItem | null {
    // 音乐条目不做影院焦点图，聚焦图只属于电影 / 剧集
    const visible = this.store.getVisibleMediaItems().filter(it => it.mediaType !== 'track');
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

  private resumeMs(itemId: string): number {
    const h = this.store.getHistoryForItem(itemId);
    return h && !h.finished && h.positionMs > 5000 ? h.positionMs : 0;
  }

  build() {
    Column() {
        // Sleek Cinema Header + Icon Search（固定 header）
        Row({ space: 10 }) {
          Row({ space: 10 }) {
            if (this.breakpoint === 'sm') {
              Image($r('app.media.ic_brand_prism'))
                .width(36)
                .height(36)
            }
            Column({ space: 1 }) {
              Text('棱镜播放器')
                .fontSize(21)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text(
                this.store.isScanning
                  ? this.store.scanStatusText
                  : (this.category === 'music'
                    ? `${this.musicAlbumCount()} 张专辑 · ${this.musicTrackCount()} 首`
                    : `${this.getFilteredMovies().length} 部电影 · ${this.getFilteredSeries().length} 部剧集` +
                      (this.musicTrackCount() > 0 ? ` · ${this.musicTrackCount()} 首音乐` : ''))
              )
                .fontSize(11)
                .fontColor(this.store.isScanning ? $r('app.color.accent_blue') : $r('app.color.text_body_muted'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

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
        }
        .padding({
          left: Layout.gutter(this.breakpoint),
          right: Layout.gutter(this.breakpoint),
          top: 16
        })
        .width('100%')

        Refresh({ refreshing: this.refreshing }) {
        Scroll() {
          Column({ space: 20 }) {
        // Hero Cinema Spotlight Banner
        if (this.category !== 'music' && this.getHeroItem() !== null) {
          Stack({ alignContent: Alignment.BottomStart }) {
            if ((this.getHeroItem()!.backdropUrl || this.getHeroItem()!.posterUrl) && !this.heroImgFailed) {
              Image(MediaArtwork.resolve(this.getHeroItem()!.backdropUrl || this.getHeroItem()!.posterUrl))
                .width('100%')
                .height(Layout.heroHeight(this.breakpoint))
                .objectFit(ImageFit.Cover)
                .borderRadius(18)
                .onError(() => {
                  this.heroImgFailed = true;
                })
            } else {
              Stack({ alignContent: Alignment.TopEnd }) {
                Column()
                  .width('100%')
                  .height(Layout.heroHeight(this.breakpoint))
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
              .height(Layout.heroHeight(this.breakpoint))
              .borderRadius(18)
            }

            Column()
              .width('100%')
              .height(Layout.heroHeight(this.breakpoint))
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
                      .fontSize(12)
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
                .fontSize(this.breakpoint === 'xl' ? 32 : (this.breakpoint === 'sm' ? 21 : 27))
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
                .constraintSize({ maxWidth: this.breakpoint === 'sm' ? 560 : 680 })

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
        if (this.category !== 'music' && this.getContinueWatching().length > 0) {
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
            }.edgeEffect(EdgeEffect.Spring)
            .scrollable(ScrollDirection.Horizontal)
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // Category Filter Chips + Secondary More Menu
        Row({ space: 8 }) {
          Scroll() {
            Row({ space: 8 }) {
              this.filterChip('全部', 'all')
              this.filterChip('电影', 'movie')
              this.filterChip('剧集', 'tv')
              this.filterChip('音乐', 'music')
              this.filterChip('收藏', 'favorite')
              if (this.store.vaultUnlocked) {
                this.filterChip('私密', 'private')
              }
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Start)
          .clip(true)

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
              value: '从相册导入视频',
              action: () => { this.store.importFromGallery(); }
            },
            {
              value: '导入文件（视频 / 音乐）',
              action: () => { this.store.importLocalVideos(); }
            },
            {
              value: '添加本机文件夹',
              action: () => { this.store.importLocalFolder(); }
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
            }
          ], appMenuOptions())
        }
        .width('100%')

        // Music Section
        if (this.category === 'music') {
          MusicLibrary({
            breakpoint: this.breakpoint,
            onPlayAlbum: (album: MusicAlbum) => this.onPlayAlbum(album),
            onOpenPlayer: () => this.onOpenMusicPlayer(),
            onImportFolder: () => { this.store.importLocalFolder(); }
          })
        }

        // Series Section
        if (this.getFilteredSeries().length > 0) {
          Column({ space: 10 }) {
            Text('剧集')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            GridRow({
              columns: 12,
              gutter: { x: 14, y: 16 },
              breakpoints: {
                value: ['600vp', '840vp', '1440vp'],
                reference: BreakpointsReference.ComponentSize
              }
            }) {
              ForEach(this.getFilteredSeries(), (grp: SeriesGroup) => {
                GridCol({ span: { xs: 4, sm: 3, md: 2, lg: 2 } }) {
                  PosterCard({
                    title: grp.title,
                    subtitle: grp.year > 0 ? `${grp.year}` : `${grp.episodes.length} 集`,
                    posterUrl: grp.posterUrl,
                    rating: grp.rating,
                    episodeCountLabel: `${grp.episodes.length} 集`,
                    onSelect: () => this.onOpenSeries(grp),
                    onPlay: () => {
                      const first = grp.episodes.length > 0 ? grp.episodes[0] : null;
                      if (first) this.onPlayDirect(first, this.resumeMs(first.id));
                    }
                  })
                }
              }, (grp: SeriesGroup) => grp.seriesKey)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // Movies Section
        if (this.getFilteredMovies().length > 0) {
          Column({ space: 10 }) {
            Row() {
              Text('电影')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              if (this.getFilteredMovies().length > 1) {
                Text('播放全部')
                  .fontSize(12)
                  .fontColor($r('app.color.accent_blue'))
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(16)
                  .backgroundColor($r('app.color.fill_subtle'))
                  .onClick(() => this.onPlayMovieList(this.getFilteredMovies()))
              }
            }
            .width('100%')

            GridRow({
              columns: 12,
              gutter: { x: 14, y: 16 },
              breakpoints: {
                value: ['600vp', '840vp', '1440vp'],
                reference: BreakpointsReference.ComponentSize
              }
            }) {
              ForEach(this.getFilteredMovies(), (item: MediaItem) => {
                GridCol({ span: { xs: 4, sm: 3, md: 2, lg: 2 } }) {
                  PosterCard({
                    title: item.title,
                    subtitle: item.year > 0 ? `${item.year}` : item.qualityTag,
                    posterUrl: item.posterUrl,
                    qualityTag: item.qualityTag,
                    rating: item.rating,
                    progressRatio: this.getProgressRatio(item.id),
                    onSelect: () => this.onOpenMovie(item),
                    onPlay: () => this.onPlayDirect(item, this.resumeMs(item.id))
                  })
                }
              }, (item: MediaItem) => item.id)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // 全部里的音乐：只摆前几张专辑，完整列表在「音乐」分类
        if (this.category === 'all' && this.musicAlbumCount() > 0) {
          Column({ space: 10 }) {
            Row() {
              Text('音乐')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.musicAlbumCount()} 张 · ${this.musicTrackCount()} 首`)
                .fontSize(11)
                .fontColor($r('app.color.text_body_muted'))
            }
            .width('100%')

            MusicLibrary({
              breakpoint: this.breakpoint,
              compact: true,
              onPlayAlbum: (album: MusicAlbum) => this.onPlayAlbum(album),
              onOpenPlayer: () => this.onOpenMusicPlayer(),
              onImportFolder: () => { this.store.importLocalFolder(); }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.category !== 'music' && this.getFilteredMovies().length === 0 &&
          this.getFilteredSeries().length === 0 && this.musicAlbumCount() === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.movie'))
              .fontSize(38)
              .fontColor([$r('app.color.text_muted')])
            Text(this.category === 'all' ? '影库是空的' : '没有匹配的内容')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            if (this.category === 'all') {
              Text('手机里的视频，或你自己的 NAS / 网盘')
                .fontSize(13)
                .fontColor($r('app.color.text_body_muted'))
                .textAlign(TextAlign.Center)
              Row({ space: 10 }) {
                Button('从相册导入视频')
                  .height(38)
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.accent_blue'))
                  .borderRadius(10)
                  .onClick(() => {
                    this.store.importFromGallery();
                  })
                Button('连接 NAS / 网盘')
                  .height(38)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_elevated'))
                  .borderRadius(10)
                  .onClick(() => this.onGoSources())
              }
            }
          }
          .width('100%')
          .padding({ top: 48, bottom: 48 })
        }
      }
      .padding({
        left: Layout.gutter(this.breakpoint),
        right: Layout.gutter(this.breakpoint),
        top: 16,
        bottom: 32
      })
      .width('100%')
      .constraintSize({ maxWidth: Layout.contentMax(this.breakpoint) + Layout.gutter(this.breakpoint) * 2 })
    }.edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .onRefreshing(async () => {
      this.refreshing = true;
      await this.store.reloadAllData();
      this.refreshing = false;
    })
    }
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

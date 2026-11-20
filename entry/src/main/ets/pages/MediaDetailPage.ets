import { BreakpointType } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { Layout } from '../common/Layout';
import { MediaArtwork } from '../common/MediaArtwork';
import {
  MediaDetailParams,
  MediaItem,
  MediaSource,
  PlayerLaunchParams,
  SeriesGroup,
  WatchHistoryRecord
} from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';
import { TmdbCandidate } from '../services/TmdbScraper';

@Entry
@ComponentV2
struct MediaDetailPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local movie: MediaItem | null = null;
  @Local series: SeriesGroup | null = null;
  @Local showScrapeSheet: boolean = false;
  @Local scrapeQuery: string = '';
  @Local scrapeBusy: boolean = false;
  @Local scrapeTip: string = '';
  @Local scrapeResults: TmdbCandidate[] = [];
  @Local backdropFailed: boolean = false;
  @Local posterFailed: boolean = false;
  @Local showTechInfo: boolean = false;
  @Local isFav: boolean = false;
  @Local refreshing: boolean = false;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as MediaDetailParams | undefined;
    if (params?.movie) {
      const latest = this.store.mediaItems.find(m => m.id === params.movie!.id);
      this.movie = latest ? latest : params.movie;
      this.isFav = this.movie.isFavorite === true;
    } else if (params?.series) {
      const latestGrp = this.store.getSeriesGroups().find(g => g.seriesKey === params.series!.seriesKey);
      this.series = latestGrp ? latestGrp : params.series;
      if (this.series.episodes.length > 0) {
        this.isFav = this.series.episodes[0].isFavorite === true;
      }
    }
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private getPrimaryItem(): MediaItem | null {
    if (this.movie) return this.movie;
    if (this.series && this.series.episodes.length > 0) return this.series.episodes[0];
    return null;
  }

  private getPrimaryHistory(): WatchHistoryRecord | undefined {
    const primary = this.getPrimaryItem();
    return primary ? this.store.getHistoryForItem(primary.id) : undefined;
  }

  private getTitle(): string {
    if (this.movie) return this.movie.title;
    if (this.series) return this.series.title;
    return '影片详情';
  }

  private getBackdrop(): string {
    if (this.movie) return this.movie.backdropUrl || this.movie.posterUrl;
    if (this.series) return this.series.backdropUrl || this.series.posterUrl;
    return '';
  }

  private getPoster(): string {
    if (this.movie) return this.movie.posterUrl;
    if (this.series) return this.series.posterUrl;
    return '';
  }

  private getYear(): number {
    return this.movie ? this.movie.year : (this.series ? this.series.year : 0);
  }

  private getRating(): number {
    return this.movie ? this.movie.rating : (this.series ? this.series.rating : 0);
  }

  private getSource(sourceId: string): MediaSource | undefined {
    return this.store.sources.find(s => s.id === sourceId);
  }

  private launchPlayer(item: MediaItem, startPosMs: number): void {
    const params: PlayerLaunchParams = {
      item,
      source: this.getSource(item.sourceId),
      startPositionMs: startPosMs,
      playlist: this.series ? this.series.episodes : undefined
    };
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/PlayerPage',
      params
    });
  }

  @Builder
  specBadge(icon: Resource, text: string, tint: ResourceColor) {
    Row({ space: 5 }) {
      Image(icon)
        .width(14)
        .height(14)
      Text(text)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(tint)
    }
    .padding({ left: 9, right: 9, top: 5, bottom: 5 })
    .borderRadius(8)
    .backgroundColor($r('app.color.fill_subtle'))
    .border({ width: 0.6, color: $r('app.color.fill_strong') })
  }

  private bp(): BreakpointType {
    return this.store.currentBreakpoint;
  }

  /** 详情页在宽窗里收窄并居中，避免简介一行拉出 2000vp。 */
  private contentWidth(): number {
    return Layout.contentWidth(this.store.windowWidthVp, this.bp(), 0);
  }

  private heroHeight(): number {
    if (this.bp() === 'sm') return 250;
    if (this.bp() === 'md') return 300;
    return 352;
  }

  private posterWidth(): number {
    return this.bp() === 'sm' ? 96 : 148;
  }

  private posterHeight(): number {
    return this.bp() === 'sm' ? 140 : 216;
  }

  /** 下拉刷新：重读影库数据并同步当前影片/剧集的最新状态。 */
  private async refreshDetail(): Promise<void> {
    await this.store.reloadAllData();
    if (this.movie) {
      const latest = this.store.mediaItems.find(m => m.id === this.movie!.id);
      if (latest) this.movie = latest;
    } else if (this.series) {
      const grp = this.store.getSeriesGroups().find(g => g.seriesKey === this.series!.seriesKey);
      if (grp) this.series = grp;
    }
  }

  build() {
    Row() {
    Column() {
      NavHeaderBar({
        inset: 0,
        title: this.getTitle(),
        subtitle: this.series ? `剧集 · 共 ${this.series.episodes.length} 集` : (this.movie?.qualityTag || '高清片源'),
        rightLabel: '刮削',
        rightIcon: $r('sys.symbol.wand_and_stars_fill'),
        onBack: () => this.getUIContext().getRouter().back(),
        onRightAction: () => {
          const primary = this.getPrimaryItem();
          if (primary) {
            this.scrapeQuery = primary.mediaType === 'episode' ? primary.seriesTitle : primary.title;
          }
          this.scrapeTip = '';
          this.showScrapeSheet = true;
        }
      })

      Refresh({ refreshing: this.refreshing }) {
      Scroll() {
        Column({ space: 18 }) {
          // Cinema Backdrop + Poster + Core Identity
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.getBackdrop() && !this.backdropFailed) {
              Image(MediaArtwork.resolve(this.getBackdrop()))
                .width('100%')
                .height(this.heroHeight())
                .objectFit(ImageFit.Cover)
                .onError(() => { this.backdropFailed = true; })
            } else {
              Stack({ alignContent: Alignment.TopEnd }) {
                Column()
                  .width('100%')
                  .height(this.heroHeight())
                  .linearGradient({
                    angle: 135,
                    colors: [
                      [MediaArtwork.paletteFor(this.getTitle()).top, 0],
                      [MediaArtwork.paletteFor(this.getTitle()).bottom, 1]
                    ]
                  })
                Image($r('app.media.art_cinema_motif'))
                  .width(260)
                  .height(150)
                  .objectFit(ImageFit.Contain)
                  .margin({ top: 10, right: 6 })
              }
              .width('100%')
              .height(this.heroHeight())
            }

            Column()
              .width('100%')
              .height(this.heroHeight())
              .linearGradient({
                angle: 180,
                colors: [['#1A0A0B0F', 0], ['#990A0B0F', 0.52], ['#FF0A0B0F', 1]]
              })

            Row({ space: 16 }) {
              if (this.getPoster() && !this.posterFailed) {
                Image(MediaArtwork.resolve(this.getPoster()))
                  .width(this.posterWidth())
                  .height(this.posterHeight())
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .border({ width: 1, color: '#44FFFFFF' })
                  .shadow({ radius: 14, color: '#CC000000', offsetX: 0, offsetY: 6 })
                  .onError(() => { this.posterFailed = true; })
              } else {
                Column({ space: 8 }) {
                  Image($r('app.media.ic_file_video'))
                    .width(34)
                    .height(34)
                  Text(this.getTitle().split(' (')[0])
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(2)
                    .textAlign(TextAlign.Center)
                    .padding({ left: 6, right: 6 })
                }
                .width(this.posterWidth())
                .height(this.posterHeight())
                .justifyContent(FlexAlign.Center)
                .linearGradient({
                  angle: 150,
                  colors: [
                    [MediaArtwork.paletteFor(this.getTitle()).top, 0],
                    [MediaArtwork.paletteFor(this.getTitle()).bottom, 1]
                  ]
                })
                .borderRadius(12)
                .border({ width: 1, color: $r('app.color.fill_strong') })
                .shadow({ radius: 14, color: '#CC000000', offsetX: 0, offsetY: 6 })
              }

              Column({ space: 7 }) {
                Text(this.getTitle())
                  .fontSize(this.bp() === 'sm' ? 22 : (this.bp() === 'xl' ? 32 : 28))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textShadow({ radius: 8, color: '#CC000000', offsetX: 0, offsetY: 2 })

                if (this.movie && this.movie.originalTitle && this.movie.originalTitle !== this.movie.title) {
                  Text(this.movie.originalTitle)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }

                Row({ space: 8 }) {
                  if (this.getYear() > 0) {
                    Text(`${this.getYear()}`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(6)
                      .backgroundColor($r('app.color.fill_strong'))
                  }
                  if (this.getRating() > 0) {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.star_fill'))
                        .fontSize(11)
                        .fontColor([$r('app.color.accent_gold')])
                      Text(this.getRating().toFixed(1))
                        .fontSize(11)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.accent_gold'))
                    }
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(6)
                    .backgroundColor('#26F5B841')
                  }
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 10 })
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')

          Column({ space: 18 }) {
            // Vector Technical Badges Strip
            if (this.getPrimaryItem()) {
              Row({ space: 8 }) {
                if (this.getPrimaryItem()!.qualityTag) {
                  this.specBadge($r('app.media.ic_codec_hw'), this.getPrimaryItem()!.qualityTag, $r('app.color.accent_cyan'))
                }
                if (this.getPrimaryItem()!.subtitleUrl) {
                  this.specBadge($r('app.media.ic_file_subtitle'), '外挂特效字幕', $r('app.color.success'))
                }
                if (this.getPrimaryItem()!.fileSize > 0) {
                  this.specBadge($r('app.media.ic_cache_proxy'), Formatters.formatBytes(this.getPrimaryItem()!.fileSize), $r('app.color.text_primary'))
                }
              }
              .width('100%')
            }

            // Primary Playback Buttons
            if (this.getPrimaryItem()) {
              Row({ space: 10 }) {
                Button() {
                  Row({ space: 8 }) {
                    SymbolGlyph($r('sys.symbol.play_fill'))
                      .fontSize(16)
                      .fontColor([Color.White])
                    Text(
                      this.getPrimaryHistory() && this.getPrimaryHistory()!.positionMs > 5000 && !this.getPrimaryHistory()!.finished
                        ? (this.bp() === 'sm'
                          ? '继续播放'
                          : `继续播放 · ${Formatters.formatDuration(this.getPrimaryHistory()!.positionMs)}`)
                        : (this.series ? '播放剧集' : '立即播放')
                    )
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .layoutWeight(1)
                .height(48)
                .backgroundColor($r('app.color.accent_blue'))
                .borderRadius(12)
                .onClick(() => {
                  const target = this.getPrimaryItem()!;
                  const h = this.getPrimaryHistory();
                  const pos = (h && !h.finished) ? h.positionMs : 0;
                  this.launchPlayer(target, pos);
                })

                Button() {
                  SymbolGlyph(this.isFav ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                    .fontSize(18)
                    .fontColor([this.isFav ? '#EF4444' : $r('app.color.text_primary')])
                }
                .width(48)
                .height(48)
                .backgroundColor($r('app.color.bg_elevated'))
                .borderRadius(12)
                .border({ width: 0.7, color: this.isFav ? '#55EF4444' : $r('app.color.border_subtle') })
                .onClick(async () => {
                  const target = this.getPrimaryItem();
                  if (target) {
                    this.isFav = await this.store.toggleFavorite(target.id);
                  }
                })

                Button() {
                  SymbolGlyph($r('sys.symbol.lock_fill'))
                    .fontSize(17)
                    .fontColor([$r('app.color.accent_gold')])
                }
                .width(48)
                .height(48)
                .backgroundColor($r('app.color.bg_elevated'))
                .borderRadius(12)
                .border({ width: 0.7, color: $r('app.color.border_subtle') })
                .onClick(() => {
                  const target = this.getPrimaryItem();
                  if (target) this.requestVaultHide(target);
                })

                if (this.getPrimaryHistory() && this.getPrimaryHistory()!.positionMs > 5000 && !this.getPrimaryHistory()!.finished) {
                  Button() {
                    Row({ space: 5 }) {
                      SymbolGlyph($r('sys.symbol.arrow_counterclockwise_clock'))
                        .fontSize(14)
                        .fontColor([$r('app.color.text_primary')])
                      Text('重播')
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                    }
                  }
                  .height(48)
                  .padding({ left: 16, right: 16 })
                  .backgroundColor($r('app.color.bg_elevated'))
                  .borderRadius(12)
                  .border({ width: 0.8, color: $r('app.color.fill_strong') })
                  .onClick(() => this.launchPlayer(this.getPrimaryItem()!, 0))
                }
              }
              .width('100%')
              .constraintSize({ maxWidth: 560 })
              .alignSelf(ItemAlign.Start)
            }

            // Synopsis
            Column({ space: 8 }) {
              Text('剧情简介')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text(
                (this.movie?.overview || this.series?.overview) ||
                '本地 NFO 与文件名解析已就绪。可在「设置 → TMDB 海报墙刮削」填入 API Key 自动拉取完整中文剧情简介、演职表与 4K 剧照。'
              )
                .fontSize(13)
                .lineHeight(this.bp() === 'sm' ? 22 : 24)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .constraintSize({ maxWidth: 780 })
            .alignItems(HorizontalAlign.Start)

            // Collapsible File & Source Technical Specification Card
            if (this.movie) {
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  Image($r('app.media.ic_file_video')).width(18).height(18)
                  Text('文件与片源详情').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  Blank()
                  Text(this.getSource(this.movie.sourceId)?.name || '本地媒体库')
                    .fontSize(12)
                    .fontColor($r('app.color.text_muted'))
                  SymbolGlyph(this.showTechInfo ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                    .fontSize(13)
                    .fontColor([$r('app.color.text_muted')])
                }
                .width('100%')
                .onClick(() => { this.showTechInfo = !this.showTechInfo; })

                if (this.showTechInfo) {
                  Divider().color($r('app.color.divider'))
                  this.techRow('文件名', this.movie.fileName)
                  this.techRow('片源位置', this.getSource(this.movie.sourceId)?.name || '本地媒体库')
                  if (this.movie.remotePath) {
                    this.techRow('远程路径', this.movie.remotePath)
                  }
                  if (this.movie.fileSize > 0) {
                    this.techRow('体积大小', Formatters.formatBytes(this.movie.fileSize))
                  }
                  if (this.movie.durationMs > 0) {
                    this.techRow('总时长', Formatters.formatDuration(this.movie.durationMs))
                  }
                  this.techRow('外挂字幕', this.movie.subtitleUrl ? '已匹配同目录字幕轨' : '待播放时手动加载或无外挂字幕')
                }
              }
              .width('100%')
              .padding(16)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_elevated'))
              .border({ width: 0.8, color: $r('app.color.border_subtle') })
              .alignItems(HorizontalAlign.Start)
            }

            // Series Episodes List
            if (this.series && this.series.episodes.length > 0) {
              Column({ space: 10 }) {
                Text(`剧集列表 · 共 ${this.series.episodes.length} 集`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))

                ForEach(this.series.episodes, (ep: MediaItem) => {
                  Column({ space: 8 }) {
                    Row({ space: 12 }) {
                      Text(`S${ep.seasonNo < 10 ? '0' + ep.seasonNo : ep.seasonNo}E${ep.episodeNo < 10 ? '0' + ep.episodeNo : ep.episodeNo}`)
                        .fontSize(12)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.accent_blue'))
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .borderRadius(7)
                        .backgroundColor('#225E8BFF')

                      Column({ space: 3 }) {
                        Text(ep.fileName)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row({ space: 8 }) {
                          Text(ep.qualityTag || '高清剧集')
                            .fontSize(11)
                            .fontColor($r('app.color.accent_cyan'))
                          if (ep.fileSize > 0) {
                            Text(Formatters.formatBytes(ep.fileSize))
                              .fontSize(11)
                              .fontColor($r('app.color.text_muted'))
                          }
                          if (ep.subtitleUrl) {
                            Image($r('app.media.ic_file_subtitle')).width(14).height(14)
                          }
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      SymbolGlyph($r('sys.symbol.play_circle_fill'))
                        .fontSize(26)
                        .fontColor([$r('app.color.accent_blue')])
                    }
                    .width('100%')

                    if (this.store.getHistoryForItem(ep.id) && this.store.getHistoryForItem(ep.id)!.durationMs > 0) {
                      Row() {
                        Row()
                          .width(`${Math.min(100, Math.round((this.store.getHistoryForItem(ep.id)!.positionMs / this.store.getHistoryForItem(ep.id)!.durationMs) * 100))}%`)
                          .height(3)
                          .backgroundColor($r('app.color.accent_blue'))
                      }
                      .width('100%')
                      .height(3)
                      .backgroundColor($r('app.color.bg_secondary'))
                      .borderRadius(2)
                    }
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.bg_elevated'))
                  .border({ width: 0.8, color: $r('app.color.border_subtle') })
                  .onClick(() => {
                    const eh = this.store.getHistoryForItem(ep.id);
                    this.launchPlayer(ep, eh && !eh.finished ? eh.positionMs : 0);
                  })
                }, (ep: MediaItem) => ep.id)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .padding({ left: 0, right: 0, bottom: 36 })
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(async () => {
        await this.refreshDetail();
        this.refreshing = false;
      })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Layout.gutter(this.bp()),
      right: Layout.gutter(this.bp()),
      top: 8
    })
    .constraintSize({ maxWidth: Layout.detailMax(this.bp()) + Layout.gutter(this.bp()) * 2 })
    .bindSheet(this.showScrapeSheet, this.scrapeSheetBuilder(), {
      height: this.bp() === 'sm'
        ? Math.round(this.store.windowHeightVp * 0.58)
        : 480,
      dragBar: false,
      title: { title: 'TMDB 刮削' },
      preferType: this.bp() === 'sm' ? SheetType.BOTTOM : SheetType.CENTER,
      width: this.bp() === 'sm' ? undefined : this.scrapeSheetWidth(),
      backgroundColor: $r('app.color.bg_elevated'),
      onDisappear: () => { this.showScrapeSheet = false; }
    })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_primary'))
  }

  /** 窗口变窄/变矮时不让弹窗超出可视区域（md 窗口可能只比 640 略宽） */
  private scrapeSheetWidth(): number {
    return Math.min(640, Math.max(420, this.store.windowWidthVp - 80));
  }

  @Builder
  scrapeSheetBuilder() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.scrapeQuery, placeholder: '输入准确的中文/英文片名或年份...' })
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.bg_primary'))
          .borderRadius(10)
          .onChange((v: string) => { this.scrapeQuery = v; })

        Button(this.scrapeBusy ? '搜索中...' : '搜索')
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(10)
          .enabled(!this.scrapeBusy)
          .onClick(() => this.runScrapeSearch())
      }
      .width('100%')

      if (this.scrapeTip) {
        Text(this.scrapeTip)
          .fontSize(12)
          .fontColor($r('app.color.accent_cyan'))
          .width('100%')
      }

      if (this.scrapeResults.length > 0) {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.scrapeResults, (cand: TmdbCandidate) => {
              Row({ space: 12 }) {
                if (cand.posterUrl) {
                  Image(cand.posterUrl)
                    .width(44)
                    .height(62)
                    .borderRadius(6)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor($r('app.color.fill_subtle'))
                } else {
                  Column() {
                    SymbolGlyph($r('sys.symbol.circle'))
                      .fontSize(18)
                      .fontColor([$r('app.color.text_muted')])
                  }
                  .width(44)
                  .height(62)
                  .borderRadius(6)
                  .backgroundColor($r('app.color.fill_subtle'))
                  .justifyContent(FlexAlign.Center)
                }

                Column({ space: 3 }) {
                  Text(cand.title || cand.originalTitle || '未命名')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 6 }) {
                    if (cand.originalTitle && cand.originalTitle !== cand.title) {
                      Text(cand.originalTitle)
                        .fontSize(11)
                        .fontColor($r('app.color.text_muted'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    if (cand.year > 0) {
                      Text(`${cand.year}`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_muted'))
                    }
                    if (cand.rating > 0) {
                      Row({ space: 3 }) {
                        SymbolGlyph($r('sys.symbol.star_fill'))
                          .fontSize(10)
                          .fontColor([$r('app.color.accent_gold')])
                        Text(cand.rating.toFixed(1))
                          .fontSize(11)
                          .fontColor($r('app.color.accent_gold'))
                      }
                    }
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(13)
                  .fontColor([$r('app.color.text_muted')])
              }
              .width('100%')
              .padding(8)
              .borderRadius(12)
              .backgroundColor($r('app.color.bg_primary'))
              .border({ width: 0.8, color: $r('app.color.border_subtle') })
              .onClick(() => this.applyScrapeCandidate(cand))
            }, (cand: TmdbCandidate) => `${cand.kind}_${cand.tmdbId}`)
          }
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
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  private async runScrapeSearch(): Promise<void> {
    const primary = this.getPrimaryItem();
    if (!primary || !this.scrapeQuery.trim() || this.scrapeBusy) return;
    this.scrapeBusy = true;
    this.scrapeTip = '';
    try {
      this.scrapeResults = await this.store.searchScrapeCandidates(primary, this.scrapeQuery.trim());
      if (this.scrapeResults.length === 0) {
        this.scrapeTip = '未找到匹配结果，可尝试英文片名或调整关键词';
      }
    } catch (e) {
      this.scrapeResults = [];
      this.scrapeTip = e instanceof Error ? e.message : '刮削搜索失败';
    } finally {
      this.scrapeBusy = false;
    }
  }

  private async applyScrapeCandidate(cand: TmdbCandidate): Promise<void> {
    const primary = this.getPrimaryItem();
    if (!primary || this.scrapeBusy) return;
    this.scrapeBusy = true;
    this.scrapeTip = '正在应用刮削结果...';
    try {
      const updated = await this.store.scrapeItemWithCandidate(primary, cand);
      if (this.movie) {
        this.movie = updated;
        this.posterFailed = false;
        this.backdropFailed = false;
      }
      this.scrapeTip = '✓ 已应用刮削结果';
      this.showScrapeSheet = false;
    } catch (e) {
      this.scrapeTip = e instanceof Error ? e.message : '应用刮削结果失败';
    } finally {
      this.scrapeBusy = false;
    }
  }


  private async requestVaultHide(target: MediaItem): Promise<void> {
    if (!this.store.hasVaultPattern()) {
      this.getUIContext().showAlertDialog({
        title: '先设置保险箱图案',
        message: '设置解锁图案后即可隐藏内容。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '去设置',
          action: () => { this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyVaultPage' }); }
        }
      });
      return;
    }
    const isSeries = target.mediaType === 'episode';
    this.getUIContext().showAlertDialog({
      title: isSeries ? `隐藏剧集「${target.seriesTitle || target.title}」？` : `隐藏「${target.title}」？`,
      message: isSeries
        ? '隐藏后将从影库、搜索与历史移出，原文件不变。'
        : '隐藏后将从影库、搜索与历史移出，原文件不变。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '隐藏到保险库',
        fontColor: $r('app.color.accent_gold'),
        action: () => {
          this.store.hideToVault(target).then(() => {
            this.getUIContext().getRouter().back();
          });
        }
      }
    });
  }

  @Builder
  techRow(label: string, val: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_muted'))
        .width(66)
      Text(val)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

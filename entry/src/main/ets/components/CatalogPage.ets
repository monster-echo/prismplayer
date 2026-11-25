import { AppConstants } from '../common/Constants';
import { appMenuOptions } from '../common/MenuSurface';
import { Layout } from '../common/Layout';
import { MediaDetailParams, MediaItem, PlayerLaunchParams, SeriesGroup } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PageShell } from '../components/PageShell';
import { PosterCard } from '../components/PosterCard';
import { AppStore } from '../services/AppStore';
import {
  CatalogDecade,
  CatalogResolution,
  CatalogSort,
  FavoriteType,
  LibraryCatalog
} from '../services/LibraryCatalog';

export type CatalogKind = 'movie' | 'tv' | 'favorite';

interface SourceChoice {
  id: string;
  name: string;
}

/**
 * 电影 / 剧集 / 收藏的分类目录页。
 *
 * 三个入口共用网格和交互，但筛选维度按类型分开：
 * 电影有画质/年代，剧集有集数，收藏有类型；片源筛选三者都有。
 */
@ComponentV2
export struct CatalogPage {
  @Param kind: CatalogKind = 'movie';
  @Local store: AppStore = AppStore.getInstance();
  @Local sort: CatalogSort = 'recent';
  @Local sourceId: string = '';
  @Local resolution: CatalogResolution = 'all';
  @Local decade: CatalogDecade = 'all';
  @Local favoriteType: FavoriteType = 'all';
  @Local refreshing: boolean = false;
  private scroller: Scroller = new Scroller();

  private allMovies(): MediaItem[] {
    return this.store.getVisibleMediaItems().filter(it => it.mediaType === 'movie');
  }

  private allSeries(): SeriesGroup[] {
    return this.store.getSeriesGroups();
  }

  private allFavorites(): MediaItem[] {
    return this.store.getFavoriteMediaItems().filter(it => it.mediaType !== 'track');
  }

  private movies(): MediaItem[] {
    return LibraryCatalog.sortItems(
      LibraryCatalog.filterMovies(this.allMovies(), this.sourceId, this.resolution, this.decade),
      this.sort
    );
  }

  private series(): SeriesGroup[] {
    return LibraryCatalog.sortSeries(
      LibraryCatalog.filterSeries(this.allSeries(), this.sourceId, this.decade),
      this.sort
    );
  }

  private favorites(): MediaItem[] {
    return LibraryCatalog.sortItems(
      LibraryCatalog.filterFavorites(this.allFavorites(), this.sourceId, this.favoriteType),
      this.sort
    );
  }

  private totalCount(): number {
    if (this.kind === 'tv') return this.allSeries().length;
    if (this.kind === 'favorite') return this.allFavorites().length;
    return this.allMovies().length;
  }

  private visibleCount(): number {
    if (this.kind === 'tv') return this.series().length;
    if (this.kind === 'favorite') return this.favorites().length;
    return this.movies().length;
  }

  private title(): string {
    if (this.kind === 'tv') return '剧集';
    if (this.kind === 'favorite') return '收藏';
    return '电影';
  }

  private subtitle(): string {
    const unit = this.kind === 'favorite' ? '项' : '部';
    return `${this.visibleCount()} ${unit}`;
  }

  private usedSources(): SourceChoice[] {
    const ids: string[] = [];
    const push = (id: string): void => {
      if (id && ids.indexOf(id) < 0) ids.push(id);
    };
    if (this.kind === 'tv') {
      const groups = this.allSeries();
      for (let i = 0; i < groups.length; i++) push(LibraryCatalog.seriesSourceId(groups[i]));
    } else if (this.kind === 'favorite') {
      const items = this.allFavorites();
      for (let i = 0; i < items.length; i++) push(items[i].sourceId);
    } else {
      const items = this.allMovies();
      for (let i = 0; i < items.length; i++) push(items[i].sourceId);
    }
    const out: SourceChoice[] = [];
    for (let i = 0; i < ids.length; i++) {
      const src = this.store.sources.find(s => s.id === ids[i]);
      out.push({ id: ids[i], name: src ? src.name : ids[i] });
    }
    out.sort((a: SourceChoice, b: SourceChoice) => a.name.localeCompare(b.name, 'zh-CN'));
    return out;
  }

  private sourceLabel(): string {
    if (!this.sourceId) return '全部片源';
    const choices = this.usedSources();
    for (let i = 0; i < choices.length; i++) {
      if (choices[i].id === this.sourceId) return choices[i].name;
    }
    return '全部片源';
  }

  private sortLabel(): string {
    if (this.sort === 'name') return '名称';
    if (this.sort === 'year') return '年份';
    if (this.sort === 'rating') return '评分';
    if (this.sort === 'duration') return '时长';
    if (this.sort === 'episodes') return '集数';
    return '最近添加';
  }

  private resolutionLabel(): string {
    if (this.resolution === '4k') return '4K';
    if (this.resolution === '1080') return '1080P';
    if (this.resolution === '720') return '720P';
    if (this.resolution === 'other') return '其他';
    return '全部';
  }

  private decadeLabel(): string {
    if (this.decade === '2020') return '2020 以后';
    if (this.decade === '2010') return '2010–2019';
    if (this.decade === '2000') return '2000–2009';
    if (this.decade === 'older') return '更早';
    if (this.decade === 'unknown') return '未知';
    return '全部';
  }

  private typeLabel(): string {
    if (this.favoriteType === 'movie') return '电影';
    if (this.favoriteType === 'episode') return '剧集';
    return '全部';
  }

  private sortMenu(): MenuElement[] {
    const out: MenuElement[] = [
      { value: '最近添加', action: () => { this.sort = 'recent'; } },
      { value: '名称', action: () => { this.sort = 'name'; } },
      { value: '年份', action: () => { this.sort = 'year'; } },
      { value: '评分', action: () => { this.sort = 'rating'; } }
    ];
    if (this.kind === 'tv') {
      out.push({ value: '集数', action: () => { this.sort = 'episodes'; } });
    } else {
      out.push({ value: '时长', action: () => { this.sort = 'duration'; } });
    }
    return out;
  }

  private sourceMenu(): MenuElement[] {
    const out: MenuElement[] = [{ value: '全部片源', action: () => { this.sourceId = ''; } }];
    const choices = this.usedSources();
    for (let i = 0; i < choices.length; i++) {
      const id = choices[i].id;
      out.push({ value: choices[i].name, action: () => { this.sourceId = id; } });
    }
    return out;
  }

  private resolutionMenu(): MenuElement[] {
    return [
      { value: '全部画质', action: () => { this.resolution = 'all'; } },
      { value: '4K', action: () => { this.resolution = '4k'; } },
      { value: '1080P', action: () => { this.resolution = '1080'; } },
      { value: '720P', action: () => { this.resolution = '720'; } },
      { value: '其他', action: () => { this.resolution = 'other'; } }
    ];
  }

  private decadeMenu(): MenuElement[] {
    return [
      { value: '全部年份', action: () => { this.decade = 'all'; } },
      { value: '2020 以后', action: () => { this.decade = '2020'; } },
      { value: '2010–2019', action: () => { this.decade = '2010'; } },
      { value: '2000–2009', action: () => { this.decade = '2000'; } },
      { value: '更早', action: () => { this.decade = 'older'; } },
      { value: '未知', action: () => { this.decade = 'unknown'; } }
    ];
  }

  private typeMenu(): MenuElement[] {
    return [
      { value: '全部类型', action: () => { this.favoriteType = 'all'; } },
      { value: '电影', action: () => { this.favoriteType = 'movie'; } },
      { value: '剧集', action: () => { this.favoriteType = 'episode'; } }
    ];
  }

  private resetFilters(): void {
    this.sort = 'recent';
    this.sourceId = '';
    this.resolution = 'all';
    this.decade = 'all';
    this.favoriteType = 'all';
  }

  private progressRatio(itemId: string): number {
    const h = this.store.getHistoryForItem(itemId);
    if (!h || h.durationMs <= 0) return 0;
    return Math.min(1, h.positionMs / h.durationMs);
  }

  private resumeMs(itemId: string): number {
    const h = this.store.getHistoryForItem(itemId);
    return h && !h.finished && h.positionMs > 5000 ? h.positionMs : 0;
  }

  private openItem(item: MediaItem): void {
    const params: MediaDetailParams = { movie: item };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/MediaDetailPage', params });
  }

  private openSeries(grp: SeriesGroup): void {
    const params: MediaDetailParams = { series: grp };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/MediaDetailPage', params });
  }

  private playItem(item: MediaItem): void {
    const hist = this.store.getHistoryForItem(item.id);
    const params: PlayerLaunchParams = {
      item: item,
      source: this.store.sources.find(s => s.id === item.sourceId),
      startPositionMs: hist && !hist.finished ? hist.positionMs : 0
    };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PlayerPage', params });
  }

  private playSeries(grp: SeriesGroup): void {
    if (grp.episodes.length === 0) return;
    this.playItem(grp.episodes[0]);
  }


  @Builder
  sortPill() {
    Text(`排序：${this.sortLabel()}`)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .height(30)
      .padding({ left: 10, right: 10 })
      .borderRadius(15)
      .backgroundColor($r('app.color.bg_elevated'))
      .border({ width: 0.7, color: $r('app.color.border_subtle') })
      .margin({ right: 8, bottom: 8 })
      .bindMenu(this.sortMenu(), appMenuOptions())
  }

  @Builder
  sourcePill() {
    Text(`片源：${this.sourceLabel()}`)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .height(30)
      .padding({ left: 10, right: 10 })
      .borderRadius(15)
      .backgroundColor($r('app.color.bg_elevated'))
      .border({ width: 0.7, color: $r('app.color.border_subtle') })
      .margin({ right: 8, bottom: 8 })
      .bindMenu(this.sourceMenu(), appMenuOptions())
  }

  @Builder
  typePill() {
    Text(`类型：${this.typeLabel()}`)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .height(30)
      .padding({ left: 10, right: 10 })
      .borderRadius(15)
      .backgroundColor($r('app.color.bg_elevated'))
      .border({ width: 0.7, color: $r('app.color.border_subtle') })
      .margin({ right: 8, bottom: 8 })
      .bindMenu(this.typeMenu(), appMenuOptions())
  }

  @Builder
  decadePill() {
    Text(`年份：${this.decadeLabel()}`)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .height(30)
      .padding({ left: 10, right: 10 })
      .borderRadius(15)
      .backgroundColor($r('app.color.bg_elevated'))
      .border({ width: 0.7, color: $r('app.color.border_subtle') })
      .margin({ right: 8, bottom: 8 })
      .bindMenu(this.decadeMenu(), appMenuOptions())
  }

  @Builder
  resolutionPill() {
    Text(`画质：${this.resolutionLabel()}`)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .height(30)
      .padding({ left: 10, right: 10 })
      .borderRadius(15)
      .backgroundColor($r('app.color.bg_elevated'))
      .border({ width: 0.7, color: $r('app.color.border_subtle') })
      .margin({ right: 8, bottom: 8 })
      .bindMenu(this.resolutionMenu(), appMenuOptions())
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      if (this.totalCount() === 0) {
        SymbolGlyph($r('sys.symbol.movie'))
          .fontSize(38)
          .fontColor([$r('app.color.text_muted')])
        Text(`还没有${this.title()}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.kind === 'favorite' ? '点详情页的收藏按钮，条目会出现在这里' : '回到影库添加片源或导入视频')
          .fontSize(13)
          .fontColor($r('app.color.text_body_muted'))
          .textAlign(TextAlign.Center)
      } else {
        SymbolGlyph($r('sys.symbol.movie'))
          .fontSize(38)
          .fontColor([$r('app.color.text_muted')])
        Text('没有匹配的内容')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('换个筛选条件试试')
          .fontSize(13)
          .fontColor($r('app.color.text_body_muted'))
        Button('重置筛选')
          .height(36)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.bg_elevated'))
          .borderRadius(10)
          .onClick(() => this.resetFilters())
      }
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
  }

  build() {
    Column() {
      NavHeaderBar({
        title: this.title(),
        subtitle: this.subtitle(),
        onBack: () => this.getUIContext().getRouter().back()
      })

      Column() {
        PageShell({ maxWidth: 1100 }) {
          Refresh({ refreshing: this.refreshing }) {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                // 筛选条：排序 + 片源 + 类型专属维度；窄屏自动换行，避免最后一个被裁切
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  this.sortPill()
                  if (this.usedSources().length > 1) {
                    this.sourcePill()
                  }
                  if (this.kind === 'favorite') {
                    this.typePill()
                  } else {
                    this.decadePill()
                  }
                  if (this.kind === 'movie') {
                    this.resolutionPill()
                  }
                }
                .width('100%')

                if (this.kind === 'tv') {
                  if (this.series().length === 0) {
                    this.emptyState()
                  } else {
                    GridRow({
                      columns: 12,
                      gutter: { x: 14, y: 16 },
                      breakpoints: {
                        value: ['600vp', '840vp', '1440vp'],
                        reference: BreakpointsReference.ComponentSize
                      }
                    }) {
                      ForEach(this.series(), (grp: SeriesGroup) => {
                        GridCol({ span: { xs: 4, sm: 3, md: 2, lg: 2 } }) {
                          PosterCard({
                            title: grp.title,
                            subtitle: this.seriesSubtitle(grp),
                            posterUrl: grp.posterUrl,
                            rating: grp.rating,
                            episodeCountLabel: `${grp.episodes.length} 集`,
                            onSelect: () => this.openSeries(grp),
                            onPlay: () => this.playSeries(grp)
                          })
                        }
                      }, (grp: SeriesGroup) => grp.seriesKey)
                    }
                    .width('100%')
                  }
                } else {
                  if (this.visibleCount() === 0) {
                    this.emptyState()
                  } else {
                    GridRow({
                      columns: 12,
                      gutter: { x: 14, y: 16 },
                      breakpoints: {
                        value: ['600vp', '840vp', '1440vp'],
                        reference: BreakpointsReference.ComponentSize
                      }
                    }) {
                      ForEach(this.kind === 'favorite' ? this.favorites() : this.movies(),
                        (item: MediaItem) => {
                          GridCol({ span: { xs: 4, sm: 3, md: 2, lg: 2 } }) {
                            PosterCard({
                              title: item.title,
                              subtitle: this.movieSubtitle(item),
                              posterUrl: item.posterUrl,
                              qualityTag: item.qualityTag,
                              rating: item.rating,
                              progressRatio: this.progressRatio(item.id),
                              onSelect: () => this.openItem(item),
                              onPlay: () => this.playItem(item)
                            })
                          }
                        }, (item: MediaItem) => item.id)
                    }
                    .width('100%')
                  }
                }
              }
              .padding({
                left: Layout.gutter(this.store.currentBreakpoint),
                right: Layout.gutter(this.store.currentBreakpoint),
                top: 8,
                bottom: 32
              })
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .align(Alignment.Top)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(async () => {
            this.refreshing = true;
            await this.store.reloadAllData();
            this.refreshing = false;
          })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  private seriesSubtitle(grp: SeriesGroup): string {
    const base = grp.year > 0 ? `${grp.year}` : `${grp.episodes.length} 集`;
    return LibraryCatalog.seriesSourceId(grp) === AppConstants.LOCAL_SOURCE_ID ? `本机 · ${grp.episodes.length} 集` : base;
  }

  private movieSubtitle(item: MediaItem): string {
    const base = item.year > 0 ? `${item.year}` : (item.qualityTag || '视频');
    return item.sourceType === 'local' ? `本机 · ${base}` : base;
  }
}

import { Formatters } from '../common/Formatters';
import { MediaArtwork } from '../common/MediaArtwork';
import { Layout } from '../common/Layout';
import { appMenuOptions } from '../common/MenuSurface';
import { MediaDetailParams, MediaItem, PlayerLaunchParams } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PageShell } from '../components/PageShell';
import { PosterCard } from '../components/PosterCard';
import { AppStore } from '../services/AppStore';
import {
  LocalFolderGroup,
  LocalSort,
  LocalTypeFilter,
  LocalVideoIndex
} from '../services/LocalVideoIndex';

type LocalViewMode = 'folders' | 'videos';

/**
 * 本机视频独立页：文件夹优先，其次才是全部视频。
 *
 * 家庭视频/手机拍摄素材没有电影元数据，先按目录找比按演员/评分找更符合直觉；
 * 排序/筛选只做文件可推断的维度（入库时间、名称、大小、时长、画质）。
 */
@Entry
@ComponentV2
struct LocalVideosPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local mode: LocalViewMode = 'folders';
  @Local sort: LocalSort = 'recent';
  @Local typeFilter: LocalTypeFilter = 'all';
  @Local activeFolder: string | null = null;
  @Local refreshing: boolean = false;
  private scroller: Scroller = new Scroller();

  onBackPress(): boolean {
    if (this.activeFolder !== null) {
      this.backToFolders();
      return true;
    }
    this.getUIContext().getRouter().back();
    return true;
  }

  private rootUri(): string {
    return this.store.getLocalSource()?.rootPath || '';
  }

  private localVideos(): MediaItem[] {
    return LocalVideoIndex.pickVideos(this.store.getVisibleMediaItems());
  }

  private folders(): LocalFolderGroup[] {
    return LocalVideoIndex.groupFolders(this.localVideos(), this.rootUri());
  }

  private folderLabel(path: string): string {
    return LocalVideoIndex.folderLabel(path, this.rootUri());
  }

  private visibleVideos(): MediaItem[] {
    let items = this.localVideos();
    if (this.activeFolder !== null) {
      const folder = this.activeFolder;
      items = items.filter((it: MediaItem) => LocalVideoIndex.folderPath(it, this.rootUri()) === folder);
    }
    items = LocalVideoIndex.filterByType(items, this.typeFilter);
    return LocalVideoIndex.sortVideos(items, this.sort);
  }

  private totalSize(items: MediaItem[]): number {
    let sum = 0;
    for (let i = 0; i < items.length; i++) {
      sum += items[i].fileSize > 0 ? items[i].fileSize : 0;
    }
    return sum;
  }

  private sortLabel(): string {
    if (this.sort === 'name') return '名称';
    if (this.sort === 'size') return '大小';
    if (this.sort === 'duration') return '时长';
    if (this.sort === 'resolution') return '画质';
    return '最近添加';
  }

  private subtitle(): string {
    if (this.store.isScanning) return this.store.scanStatusText;
    const size = Formatters.formatBytes(this.totalSize(this.visibleVideos()));
    if (this.activeFolder !== null) {
      return `${this.visibleVideos().length} 部 · ${size}`;
    }
    if (this.mode === 'folders') {
      return `${this.folders().length} 个文件夹 · ${this.localVideos().length} 部视频`;
    }
    return `${this.visibleVideos().length} 部 · ${size}`;
  }

  private emptyTitle(): string {
    if (this.activeFolder !== null) return '这个文件夹里没有视频';
    if (this.localVideos().length === 0) {
      return this.store.getLocalSource()?.rootPath ? '还没有本机视频' : '还没有选择本机文件夹';
    }
    return '没有匹配的视频';
  }

  private emptyHint(): string {
    if (this.activeFolder !== null) return '换个文件夹，或把类型切回「全部」';
    if (!this.store.getLocalSource()?.rootPath) return '在片源管理里添加本机文件夹后扫描';
    if (this.localVideos().length === 0) return '点「重新扫描」把本机文件夹加入影库';
    return '换个类型筛选试试';
  }

  private hasLocalRoot(): boolean {
    return !!this.store.getLocalSource()?.rootPath;
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

  private openFolder(path: string): void {
    this.activeFolder = path;
    this.mode = 'videos';
    this.typeFilter = 'all';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private backToFolders(): void {
    this.activeFolder = null;
    this.mode = 'folders';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private openDetail(item: MediaItem): void {
    const params: MediaDetailParams = { movie: item };
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

  private goSources(): void {
    this.store.requestTab(1);
    this.getUIContext().getRouter().back();
  }

  private async rescan(): Promise<void> {
    const src = this.store.getLocalSource();
    if (!src) return;
    await this.store.scanSource(src);
  }

  private switchMode(next: LocalViewMode): void {
    if (this.mode === next) return;
    this.mode = next;
    this.activeFolder = null;
    this.typeFilter = 'all';
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  @Builder
  modeTab(label: string, value: LocalViewMode) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.mode === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.mode === value ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.mode === value ? $r('app.color.accent_blue') : $r('app.color.bg_elevated'))
      .border({
        width: 0.8,
        color: this.mode === value ? $r('app.color.accent_blue') : $r('app.color.border_subtle')
      })
      .onClick(() => this.switchMode(value))
  }

  @Builder
  typeChip(label: string, value: LocalTypeFilter) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.typeFilter === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.typeFilter === value ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(14)
      .backgroundColor(this.typeFilter === value ? $r('app.color.accent_blue') : $r('app.color.bg_elevated'))
      .border({
        width: 0.7,
        color: this.typeFilter === value ? $r('app.color.accent_blue') : $r('app.color.border_subtle')
      })
      .onClick(() => { this.typeFilter = value; })
  }

  @Builder
  sortButton() {
    Text(`排序：${this.sortLabel()}`)
      .fontSize(12)
      .fontColor($r('app.color.accent_blue'))
      .height(32)
      .padding({ left: 12, right: 12 })
      .borderRadius(16)
      .backgroundColor($r('app.color.fill_subtle'))
      .bindMenu([
        { value: '最近添加', action: () => { this.sort = 'recent'; } },
        { value: '名称', action: () => { this.sort = 'name'; } },
        { value: '大小', action: () => { this.sort = 'size'; } },
        { value: '时长', action: () => { this.sort = 'duration'; } },
        { value: '画质', action: () => { this.sort = 'resolution'; } }
      ], appMenuOptions())
  }

  @Builder
  folderCard(group: LocalFolderGroup) {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (group.coverUrl) {
          Image(MediaArtwork.resolve(group.coverUrl))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Image($r('app.media.ic_file_folder'))
              .width(34)
              .height(34)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .linearGradient({
            angle: 145,
            colors: [
              [MediaArtwork.paletteFor(group.name).top, 0],
              [MediaArtwork.paletteFor(group.name).bottom, 1]
            ]
          })
        }

        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [['#00000000', 0.38], ['#CC0A0B0F', 1]]
          })
          .hitTestBehavior(HitTestMode.None)

        Text(`${group.items.length} 部`)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(5)
          .backgroundColor('#B3000000')
          .margin({ left: 10, bottom: 8 })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .borderRadius(14)
      .clip(true)
      .border({ width: 0.8, color: $r('app.color.fill_strong') })

      Text(group.name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(`${group.items.length} 部 · ${Formatters.formatBytes(group.totalSize)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_body_muted'))
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.openFolder(group.path))
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      Image($r('app.media.ic_file_folder'))
        .width(44)
        .height(44)
        .opacity(0.75)
      Text(this.emptyTitle())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(this.emptyHint())
        .fontSize(12)
        .fontColor($r('app.color.text_body_muted'))
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 320 })
      Row({ space: 10 }) {
        if (this.localVideos().length === 0) {
          if (this.hasLocalRoot()) {
            Button(this.store.isScanning ? '扫描中...' : '重新扫描')
              .height(36)
              .fontSize(12)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.accent_blue'))
              .borderRadius(10)
              .enabled(!this.store.isScanning)
              .onClick(() => { this.rescan(); })
          }
          Button('片源管理')
            .height(36)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_elevated'))
            .borderRadius(10)
            .border({ width: 0.7, color: $r('app.color.fill_strong') })
            .onClick(() => this.goSources())
        } else {
          Button('查看全部')
            .height(36)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_elevated'))
            .borderRadius(10)
            .border({ width: 0.7, color: $r('app.color.fill_strong') })
            .onClick(() => { this.typeFilter = 'all'; })
        }
      }
      .padding({ top: 2 })
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
  }

  build() {
    Column() {
      NavHeaderBar({
        title: this.activeFolder !== null ? this.folderLabel(this.activeFolder) : '本机视频',
        subtitle: this.subtitle(),
        onBack: () => {
          if (this.activeFolder !== null) {
            this.backToFolders();
          } else {
            this.getUIContext().getRouter().back();
          }
        }
      })

      Column() {
      PageShell({ maxWidth: 1100 }) {
        Refresh({ refreshing: this.refreshing }) {
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              if (this.activeFolder === null) {
                Row({ space: 8 }) {
                  this.modeTab('文件夹', 'folders')
                  this.modeTab('全部视频', 'videos')
                  Blank()
                  if (this.mode === 'videos') {
                    this.sortButton()
                  }
                }
                .width('100%')
              }

              if (this.mode === 'videos' || this.activeFolder !== null) {
                Row({ space: 8 }) {
                  this.typeChip('全部', 'all')
                  this.typeChip('电影', 'movie')
                  this.typeChip('剧集', 'episode')
                  Blank()
                  if (this.activeFolder !== null) {
                    this.sortButton()
                  }
                }
                .width('100%')
              }

              if (this.mode === 'folders' && this.activeFolder === null) {
                if (this.folders().length === 0) {
                  this.emptyState()
                } else {
                  GridRow({
                    columns: 12,
                    gutter: { x: 12, y: 16 },
                    breakpoints: {
                      value: ['600vp', '840vp', '1440vp'],
                      reference: BreakpointsReference.ComponentSize
                    }
                  }) {
                    ForEach(this.folders(), (group: LocalFolderGroup) => {
                      GridCol({ span: { xs: 6, sm: 4, md: 3, lg: 2 } }) {
                        this.folderCard(group)
                      }
                    }, (group: LocalFolderGroup) => group.path || '__root__')
                  }
                  .width('100%')
                }
              } else {
                if (this.visibleVideos().length === 0) {
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
                    ForEach(this.visibleVideos(), (item: MediaItem) => {
                      GridCol({ span: { xs: 4, sm: 3, md: 2, lg: 2 } }) {
                        PosterCard({
                          title: item.title,
                          subtitle: item.year > 0 ? `${item.year}` : (item.qualityTag || '视频'),
                          posterUrl: item.posterUrl,
                          qualityTag: item.qualityTag,
                          rating: item.rating,
                          progressRatio: this.progressRatio(item.id),
                          onSelect: () => this.openDetail(item),
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
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 24 })
              .onActionEnd((event: GestureEvent) => {
                // 文件夹 / 全部视频 是同级视图，左右划直接切换
                if (this.activeFolder !== null) return;
                if (event.offsetX <= -60 && this.mode === 'folders') {
                  this.switchMode('videos');
                } else if (event.offsetX >= 60 && this.mode === 'videos') {
                  this.switchMode('folders');
                }
              })
          )
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
}

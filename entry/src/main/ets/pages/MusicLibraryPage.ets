import { appMenuOptions } from '../common/MenuSurface';
import { Layout } from '../common/Layout';
import { MediaItem, MusicAlbum, MusicLaunchParams } from '../common/Types';
import { MusicLibrary } from '../components/MusicLibrary';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PageShell } from '../components/PageShell';
import { AppStore } from '../services/AppStore';

interface MusicSourceChoice {
  id: string;
  name: string;
}

@Entry
@ComponentV2
struct MusicLibraryPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local sourceId: string = '';
  @Local sortMode: string = 'recent';
  @Local refreshing: boolean = false;

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private allAlbums(): MusicAlbum[] {
    return this.store.getMusicAlbums();
  }

  private visibleAlbums(): MusicAlbum[] {
    const all = this.allAlbums();
    if (!this.sourceId) return all;
    return all.filter((album: MusicAlbum) =>
      album.tracks.length > 0 && album.tracks[0].sourceId === this.sourceId);
  }

  private trackCount(): number {
    const albums = this.visibleAlbums();
    let count = 0;
    for (let i = 0; i < albums.length; i++) count += albums[i].tracks.length;
    return count;
  }

  private subtitle(): string {
    if (this.visibleAlbums().length === 0) return '还没有音乐';
    return `${this.visibleAlbums().length} 张专辑 · ${this.trackCount()} 首`;
  }

  private sources(): MusicSourceChoice[] {
    const ids: string[] = [];
    const albums = this.allAlbums();
    for (let i = 0; i < albums.length; i++) {
      const track = albums[i].tracks.length > 0 ? albums[i].tracks[0] : null;
      if (track && track.sourceId && ids.indexOf(track.sourceId) < 0) ids.push(track.sourceId);
    }
    const out: MusicSourceChoice[] = [];
    for (let i = 0; i < ids.length; i++) {
      const src = this.store.sources.find(s => s.id === ids[i]);
      out.push({ id: ids[i], name: src ? src.name : ids[i] });
    }
    out.sort((a: MusicSourceChoice, b: MusicSourceChoice) => a.name.localeCompare(b.name, 'zh-CN'));
    return out;
  }

  private sourceLabel(): string {
    if (!this.sourceId) return '全部片源';
    const list = this.sources();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === this.sourceId) return list[i].name;
    }
    return '全部片源';
  }

  private sortLabel(): string {
    if (this.sortMode === 'name') return '专辑名';
    if (this.sortMode === 'artist') return '歌手';
    return '最近添加';
  }

  private sortMenu(): MenuElement[] {
    return [
      { value: '最近添加', action: () => { this.sortMode = 'recent'; } },
      { value: '专辑名', action: () => { this.sortMode = 'name'; } },
      { value: '歌手', action: () => { this.sortMode = 'artist'; } }
    ];
  }

  private sourceMenu(): MenuElement[] {
    const out: MenuElement[] = [{ value: '全部片源', action: () => { this.sourceId = ''; } }];
    const list = this.sources();
    for (let i = 0; i < list.length; i++) {
      const id = list[i].id;
      out.push({ value: list[i].name, action: () => { this.sourceId = id; } });
    }
    return out;
  }

  private playAlbum(album: MusicAlbum): void {
    if (album.tracks.length === 0) return;
    const params: MusicLaunchParams = { item: album.tracks[0], queue: album.tracks };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/MusicPlayerPage', params });
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

  build() {
    Column() {
      NavHeaderBar({
        title: '音乐',
        subtitle: this.subtitle(),
        onBack: () => this.getUIContext().getRouter().back()
      })

      Column() {
        PageShell({ maxWidth: 1100 }) {
          Refresh({ refreshing: this.refreshing }) {
            Scroll() {
              Column({ space: 16 }) {
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  this.sortPill()
                  if (this.sources().length > 1) {
                    this.sourcePill()
                  }
                }
                .width('100%')

                MusicLibrary({
                  breakpoint: this.store.currentBreakpoint,
                  compact: false,
                  sourceId: this.sourceId,
                  sortMode: this.sortMode,
                  onPlayAlbum: (album: MusicAlbum) => this.playAlbum(album),
                  onOpenPlayer: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/MusicPlayerPage' }),
                  onImportFolder: () => { this.store.importLocalFolder(); }
                })
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
}

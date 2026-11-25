import { BreakpointType } from '../common/Constants';
import { MediaArtwork } from '../common/MediaArtwork';
import { MusicAlbum } from '../common/Types';
import { AppStore } from '../services/AppStore';
import { MusicPlayerService } from '../services/MusicPlayerService';

/**
 * 影库「音乐」分类。
 *
 * 播放队列在音乐播放页里管理，这里只做两件事：把专辑摆出来、把正在播放的现场摆在最上面。
 * 点专辑 = 整张顺序播放，选单曲在播放页队列里点。
 */
@ComponentV2
export struct MusicLibrary {
  @Param breakpoint: BreakpointType = 'sm';
  /** 首页「全部」里的精简版：只摆前几张专辑，不带正在播放和空态 */
  @Param compact: boolean = false;
  /** 音乐独立页的片源筛选：空串 = 全部 */
  @Param sourceId: string = '';
  /** 音乐独立页排序：最近添加 / 专辑名 / 歌手 */
  @Param sortMode: string = 'recent';
  @Param onPlayAlbum: (album: MusicAlbum) => void = () => {};
  @Param onOpenPlayer: () => void = () => {};
  @Param onImportFolder: () => void = () => {};
  @Local store: AppStore = AppStore.getInstance();
  @Local service: MusicPlayerService = MusicPlayerService.getInstance();
  @Local coverFailedKey: string = '';

  private albums(): MusicAlbum[] {
    let all = this.store.getMusicAlbums();
    if (this.sourceId) {
      all = all.filter((album: MusicAlbum) =>
        album.tracks.length > 0 && album.tracks[0].sourceId === this.sourceId);
    }
    if (this.sortMode === 'name') {
      all.sort((a: MusicAlbum, b: MusicAlbum) => a.album.localeCompare(b.album, 'zh-CN'));
    } else if (this.sortMode === 'artist') {
      all.sort((a: MusicAlbum, b: MusicAlbum) => a.artist.localeCompare(b.artist, 'zh-CN'));
    } else {
      all.sort((a: MusicAlbum, b: MusicAlbum) => MusicLibrary.latestAt(b) - MusicLibrary.latestAt(a));
    }
    return this.compact ? all.slice(0, 4) : all;
  }

  private static latestAt(album: MusicAlbum): number {
    let latest = 0;
    for (let i = 0; i < album.tracks.length; i++) {
      latest = Math.max(latest, album.tracks[i].addedAt || 0);
    }
    return latest;
  }

  private totalTracks(): number {
    const albums = this.albums();
    let count = 0;
    for (let i = 0; i < albums.length; i++) count += albums[i].tracks.length;
    return count;
  }

  private isAlbumPlaying(album: MusicAlbum): boolean {
    const cur = this.service.current;
    if (!cur) return false;
    return cur.album === album.album && cur.sourceId === album.tracks[0].sourceId;
  }

  @Builder
  albumCard(album: MusicAlbum) {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (album.coverUrl && this.coverFailedKey !== album.albumKey) {
          Image(MediaArtwork.resolve(album.coverUrl))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(14)
            .onError(() => {
              this.coverFailedKey = album.albumKey;
            })
        } else {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.music_note_list'))
              .fontSize(30)
              .fontColor(['#CCFFFFFF'])
          }
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 145,
            colors: [
              [MediaArtwork.paletteFor(album.album).top, 0],
              [MediaArtwork.paletteFor(album.album).bottom, 1]
            ]
          })
          .borderRadius(14)
        }

        if (this.isAlbumPlaying(album)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.music_note_list'))
              .fontSize(12)
              .fontColor([Color.White])
            Text(this.service.isPlaying ? '播放中' : '已暂停')
              .fontSize(10)
              .fontColor(Color.White)
          }
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor('#B32563EB')
          .margin(6)
        }
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(14)
      .border({ width: 0.8, color: $r('app.color.fill_strong') })

      Text(album.album)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(album.artist)
        .fontSize(11)
        .fontColor($r('app.color.text_body_muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .onClick(() => this.onPlayAlbum(album))
  }

  build() {
    Column({ space: this.compact ? 10 : 14 }) {
      if (!this.compact && this.service.hasQueue && this.service.current) {
        Row({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.service.current!.posterUrl) {
              Image(MediaArtwork.resolve(this.service.current!.posterUrl))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
            } else {
              SymbolGlyph($r('sys.symbol.music_note_list'))
                .fontSize(18)
                .fontColor(['#D9FFFFFF'])
            }
          }
          .width(44)
          .height(44)
          .borderRadius(10)
          .backgroundColor(MediaArtwork.paletteFor(this.service.current!.album || 'music').top)

          Column({ space: 2 }) {
            Text(this.service.current!.title)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.service.current!.artist || '未知歌手'} · ${this.service.isPlaying ? '正在播放' : '已暂停'}`)
              .fontSize(11)
              .fontColor($r('app.color.text_body_muted'))
              .maxLines(1)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.service.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
              .fontSize(18)
              .fontColor([Color.White])
          }
          .width(38)
          .height(38)
          .backgroundColor($r('app.color.accent_blue'))
          .onClick(() => {
            this.service.toggle();
          })
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor($r('app.color.bg_elevated'))
        .border({ width: 0.8, color: $r('app.color.fill_strong') })
        .onClick(() => this.onOpenPlayer())
      }

      if (!this.compact && this.albums().length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(38)
            .fontColor([$r('app.color.text_muted')])
          Text('还没有音乐')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('把音乐文件夹加入本机存储，或在 NAS / 网盘片源里扫描音频目录')
            .fontSize(12)
            .fontColor($r('app.color.text_body_muted'))
            .textAlign(TextAlign.Center)
          Button('添加本机文件夹')
            .height(36)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(10)
            .onClick(() => this.onImportFolder())
        }
        .width('100%')
        .padding({ top: 36, bottom: 36 })
      } else if (this.albums().length > 0) {
        if (!this.compact) {
          Row() {
            Text('专辑')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.albums().length} 张 · ${this.totalTracks()} 首`)
              .fontSize(11)
              .fontColor($r('app.color.text_body_muted'))
          }
          .width('100%')
        }

        GridRow({
          columns: 12,
          gutter: { x: 12, y: 16 },
          breakpoints: {
            value: ['600vp', '840vp', '1440vp'],
            reference: BreakpointsReference.ComponentSize
          }
        }) {
          ForEach(this.albums(), (album: MusicAlbum) => {
            GridCol({ span: { xs: 4, sm: 3, md: 2, lg: 2 } }) {
              this.albumCard(album)
            }
          }, (album: MusicAlbum) => album.albumKey)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

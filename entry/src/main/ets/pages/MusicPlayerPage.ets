import { common } from '@kit.AbilityKit';
import { MediaArtwork } from '../common/MediaArtwork';
import { Formatters } from '../common/Formatters';
import { MusicLaunchParams, MediaItem } from '../common/Types';
import { PageShell } from '../components/PageShell';
import { AppStore } from '../services/AppStore';
import { MusicPlayerService, MusicRepeatMode } from '../services/MusicPlayerService';

/**
 * 音乐播放页。
 *
 * 只是 MusicPlayerService 的一个视图：队列、进度、播放状态都在服务里，
 * 退出页面音乐继续放，锁屏 / 控制中心走 AVSession。
 */
@Entry
@ComponentV2
struct MusicPlayerPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local service: MusicPlayerService = MusicPlayerService.getInstance();
  @Local coverFailed: boolean = false;
  @Local dragging: boolean = false;
  @Local sliderMs: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.service.setContext(ctx);
    const params = this.getUIContext().getRouter().getParams() as MusicLaunchParams | undefined;
    if (params && params.item) {
      const queue = params.queue && params.queue.length > 0 ? params.queue : [params.item];
      const index = queue.findIndex(t => t.id === params.item.id);
      this.service.setQueue(queue, index >= 0 ? index : 0, true);
    }
    this.coverFailed = false;
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private repeatLabel(mode: MusicRepeatMode): string {
    if (mode === 'one') return '单曲循环';
    if (mode === 'off') return '顺序播放';
    return '列表循环';
  }

  private displayMs(): number {
    return this.dragging ? this.sliderMs : this.service.positionMs;
  }

  private coverSize(): number {
    return Math.max(200, Math.min(320, this.store.windowWidthVp - 96));
  }

  private coverOf(item: MediaItem | null): string {
    if (!item || !item.posterUrl || this.coverFailed) return '';
    return item.posterUrl;
  }

  @Builder
  coverBlock(item: MediaItem) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.coverOf(item)) {
        Image(MediaArtwork.resolve(this.coverOf(item)))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(24)
          .onError(() => {
            this.coverFailed = true;
          })
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(64)
            .fontColor(['#D9FFFFFF'])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .linearGradient({
          angle: 145,
          colors: [
            [MediaArtwork.paletteFor(item.album || item.title).top, 0],
            [MediaArtwork.paletteFor(item.album || item.title).bottom, 1]
          ]
        })
      }
    }
    .width(this.coverSize())
    .height(this.coverSize())
    .borderRadius(24)
    .border({ width: 0.8, color: $r('app.color.fill_strong') })
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 10 })
  }

  @Builder
  transportButton(symbol: Resource, size: number, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(size)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(52)
    .height(52)
    .backgroundColor($r('app.color.bg_elevated'))
    .border({ width: 0.8, color: $r('app.color.fill_strong') })
    .onClick(onTap)
  }

  build() {
    Stack() {
      PageShell({ maxWidth: 760 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height(360)
          .linearGradient({
            angle: 180,
            colors: [
              [MediaArtwork.paletteFor(this.service.current ? (this.service.current.album || this.service.current.title) : 'music').top, 0],
              ['#00000000', 1]
            ]
          })
          .opacity(0.55)

        Column({ space: 0 }) {
          // 顶栏：返回 + 正在播放 + 队列入口（队列在正文里，按钮只负责滚动定位）
          Row({ space: 10 }) {
            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_chevron_left'))
                .width(16)
                .height(16)
                .fillColor($r('app.color.text_primary'))
            }
            .width(38)
            .height(38)
            .backgroundColor($r('app.color.bg_elevated'))
            .border({ width: 0.8, color: $r('app.color.fill_strong') })
            .onClick(() => this.getUIContext().getRouter().back())

            Column({ space: 2 }) {
              Text('正在播放')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              if (this.service.current) {
                Text(`${this.service.currentIndex + 1} / ${this.service.queue.length} · ${this.service.current.qualityTag}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_body_muted'))
                  .maxLines(1)
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.list_bullet'))
                .fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(38)
            .height(38)
            .backgroundColor($r('app.color.bg_elevated'))
            .border({ width: 0.8, color: $r('app.color.fill_strong') })
            .onClick(() => { this.openQueue(); })
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 12, bottom: 10 })

          if (this.service.current === null) {
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.music_note_list'))
                .fontSize(44)
                .fontColor([$r('app.color.text_muted')])
              Text('还没有正在播放的音乐')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text('在影库「音乐」里选一首开始')
                .fontSize(12)
                .fontColor($r('app.color.text_body_muted'))
            }
            .width('100%')
            .padding({ top: 120 })
          } else {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                this.coverBlock(this.service.current)

                Column({ space: 4 }) {
                  Text(this.service.current.title)
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center)
                  Text(`${this.service.current.artist || '未知歌手'} · ${this.service.current.album || '未知专辑'}`)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Center)

                if (this.service.errorText) {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.exclamationmark_circle_fill'))
                      .fontSize(14)
                      .fontColor([$r('app.color.danger')])
                    Text(this.service.errorText)
                      .fontSize(12)
                      .fontColor($r('app.color.danger'))
                      .layoutWeight(1)
                      .maxLines(2)
                  }
                  .width('100%')
                  .padding(10)
                  .borderRadius(10)
                  .backgroundColor('#1AC81E1E')
                }

                Column({ space: 2 }) {
                  Slider({
                    value: this.displayMs(),
                    min: 0,
                    max: Math.max(1, this.service.durationMs),
                    style: SliderStyle.OutSet
                  })
                    .width('100%')
                    .blockColor($r('app.color.accent_blue'))
                    .trackColor($r('app.color.fill_subtle'))
                    .selectedColor($r('app.color.accent_blue'))
                    .onChange((value: number, mode: SliderChangeMode) => {
                      if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                        this.dragging = true;
                        this.sliderMs = value;
                      } else {
                        this.dragging = false;
                        this.service.seekTo(value);
                      }
                    })

                  Row() {
                    Text(Formatters.formatDuration(this.displayMs()))
                      .fontSize(11)
                      .fontColor($r('app.color.text_body_muted'))
                    Blank()
                    Text(Formatters.formatDuration(this.service.durationMs))
                      .fontSize(11)
                      .fontColor($r('app.color.text_body_muted'))
                  }
                  .width('100%')
                }
                .width('100%')

                Row({ space: 26 }) {
                  this.transportButton($r('sys.symbol.backward_end_fill'), 22, () => { this.service.prev(); })

                  Button({ type: ButtonType.Circle }) {
                    if (this.service.isBuffering && !this.service.isPlaying) {
                      LoadingProgress()
                        .width(26)
                        .height(26)
                        .color(Color.White)
                    } else {
                      SymbolGlyph(this.service.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
                        .fontSize(28)
                        .fontColor([Color.White])
                    }
                  }
                  .width(68)
                  .height(68)
                  .backgroundColor($r('app.color.accent_blue'))
                  .shadow({ radius: 16, color: '#552563EB', offsetX: 0, offsetY: 6 })
                  .onClick(() => { this.service.toggle(); })

                  this.transportButton($r('sys.symbol.forward_end_fill'), 22, () => { this.service.next(); })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)

                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.repeat_play'))
                    .fontSize(14)
                    .fontColor([this.service.repeatMode === 'all' ? $r('app.color.text_muted') : $r('app.color.accent_blue')])
                  Text(this.repeatLabel(this.service.repeatMode))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(14)
                .backgroundColor(this.service.repeatMode === 'all' ? $r('app.color.bg_elevated') : $r('app.color.nav_active_bg'))
                .border({ width: 0.7, color: this.service.repeatMode === 'all' ? $r('app.color.border_subtle') : $r('app.color.nav_active_border') })
                .onClick(() => { this.service.cycleRepeat(); })

                // 队列
                Column({ space: 8 }) {
                  Row() {
                    Text('播放队列')
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text(`${this.service.queue.length} 首`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_body_muted'))
                  }
                  .width('100%')
                  .id('music_queue')

                  ForEach(this.service.queue, (track: MediaItem, index: number) => {
                    Row({ space: 10 }) {
                      Text(`${index + 1}`)
                        .fontSize(11)
                        .fontColor(this.service.currentIndex === index ? $r('app.color.accent_blue') : $r('app.color.text_muted'))
                        .width(22)

                      Column({ space: 2 }) {
                        Text(track.title)
                          .fontSize(13)
                          .fontWeight(this.service.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
                          .fontColor(this.service.currentIndex === index ? $r('app.color.accent_blue') : $r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(track.artist || '未知歌手')
                          .fontSize(10)
                          .fontColor($r('app.color.text_body_muted'))
                          .maxLines(1)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      Text(Formatters.formatDuration(track.durationMs))
                        .fontSize(10)
                        .fontColor($r('app.color.text_muted'))
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 8, left: 10, right: 10 })
                    .borderRadius(10)
                    .backgroundColor(this.service.currentIndex === index ? $r('app.color.nav_active_bg') : Color.Transparent)
                    .onClick(() => {
                      if (index !== this.service.currentIndex) {
                        this.service.playIndex(index);
                      }
                    })
                  }, (track: MediaItem) => track.id)
                }
                .width('100%')
                .padding(12)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.fill_strong') })
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ left: 18, right: 18, bottom: 32 })
              .alignItems(HorizontalAlign.Center)
            }
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
      }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_primary'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  /** 队列在长页面底部：点顶栏按钮直接滚到底，省一次额外面板。 */
  private openQueue(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }
}

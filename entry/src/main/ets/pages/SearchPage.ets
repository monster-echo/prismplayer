import { Formatters } from '../common/Formatters';
import { MediaArtwork } from '../common/MediaArtwork';
import { MediaDetailParams, MediaItem, PlayerLaunchParams } from '../common/Types';
import { AppStore } from '../services/AppStore';

type SearchFilterKind = 'all' | '4k' | 'sub' | 'watching';

@Entry
@ComponentV2
struct SearchPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local query: string = '';
  @Local filterKind: SearchFilterKind = 'all';

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private getResults(): MediaItem[] {
    const q = this.query.trim().toLowerCase();
    return this.store.getVisibleMediaItems().filter((it: MediaItem) => {
      if (this.filterKind === '4k' && !it.qualityTag.toUpperCase().includes('4K') && !it.qualityTag.toUpperCase().includes('2160')) {
        return false;
      }
      if (this.filterKind === 'sub' && !it.subtitleUrl) {
        return false;
      }
      if (this.filterKind === 'watching') {
        const h = this.store.getHistoryForItem(it.id);
        if (!h || h.finished || h.positionMs <= 2000) return false;
      }
      if (!q) return true;
      return it.title.toLowerCase().includes(q) ||
        it.originalTitle.toLowerCase().includes(q) ||
        it.fileName.toLowerCase().includes(q) ||
        it.seriesTitle.toLowerCase().includes(q);
    });
  }

  private openDetail(item: MediaItem): void {
    const params: MediaDetailParams = { movie: item };
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/MediaDetailPage',
      params
    });
  }

  private playItem(item: MediaItem): void {
    const hist = this.store.getHistoryForItem(item.id);
    const params: PlayerLaunchParams = {
      item,
      source: this.store.sources.find(s => s.id === item.sourceId),
      startPositionMs: hist && !hist.finished ? hist.positionMs : 0
    };
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/PlayerPage',
      params
    });
  }

  @Builder
  chip(label: string, kind: SearchFilterKind) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.filterKind === kind ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.filterKind === kind ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 13, right: 13, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.filterKind === kind ? $r('app.color.accent_blue') : $r('app.color.bg_elevated'))
      .border({ width: 0.7, color: this.filterKind === kind ? $r('app.color.accent_blue') : $r('app.color.border_subtle') })
      .onClick(() => { this.filterKind = kind; })
  }

  build() {
    Column({ space: 12 }) {
      // Top Search Bar with Back button
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.bg_elevated'))
        .border({ width: 0.8, color: $r('app.color.fill_strong') })
        .onClick(() => this.getUIContext().getRouter().back())

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([$r('app.color.text_muted')])
          TextInput({ text: this.query, placeholder: '搜索片名、原盘文件名、演员或编码...' })
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_muted'))
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 0 })
            .defaultFocus(true)
            .onChange((val: string) => { this.query = val; })

          if (this.query) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(16)
              .fontColor([$r('app.color.text_muted')])
              .onClick(() => { this.query = ''; })
          }
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 12, right: 10 })
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_elevated'))
        .border({ width: 0.8, color: $r('app.color.fill_strong') })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12 })

      Scroll() {
        Row({ space: 8 }) {
          this.chip('全部影片', 'all')
          this.chip('4K / 2160P', '4k')
          this.chip('已配外挂字幕', 'sub')
          this.chip('正在观看', 'watching')
        }
        .padding({ left: 18, right: 18 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .width('100%')

      Text(`匹配 ${this.getResults().length} 项`)
        .fontSize(12)
        .fontColor($r('app.color.text_muted'))
        .padding({ left: 20, right: 20 })
        .width('100%')

      if (this.getResults().length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(38)
            .fontColor([$r('app.color.text_muted')])
          Text('未找到相关影片')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('尝试更换关键词或清除筛选条件')
            .fontSize(12)
            .fontColor($r('app.color.text_muted'))
        }
        .width('100%')
        .padding({ top: 72 })
      } else {
        List({ space: 10 }) {
          ForEach(this.getResults(), (item: MediaItem) => {
            ListItem() {
              Row({ space: 12 }) {
                if (item.posterUrl) {
                  Image(MediaArtwork.resolve(item.posterUrl))
                    .width(58)
                    .height(84)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(8)
                } else {
                  Column() {
                    Image($r('app.media.ic_file_video')).width(24).height(24)
                  }
                  .width(58)
                  .height(84)
                  .justifyContent(FlexAlign.Center)
                  .linearGradient({
                    angle: 145,
                    colors: [
                      [MediaArtwork.paletteFor(item.title).top, 0],
                      [MediaArtwork.paletteFor(item.title).bottom, 1]
                    ]
                  })
                  .borderRadius(8)
                }

                Column({ space: 4 }) {
                  Text(item.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(item.fileName)
                    .fontSize(11)
                    .fontColor($r('app.color.text_muted'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row({ space: 6 }) {
                    if (item.year > 0) {
                      Text(`${item.year}`).fontSize(11).fontColor($r('app.color.text_secondary'))
                    }
                    if (item.qualityTag) {
                      Text(item.qualityTag)
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.accent_cyan'))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(4)
                        .backgroundColor('#1F38BDF8')
                    }
                    if (item.subtitleUrl) {
                      Image($r('app.media.ic_file_subtitle')).width(14).height(14)
                    }
                    if (item.fileSize > 0) {
                      Text(Formatters.formatBytes(item.fileSize))
                        .fontSize(11)
                        .fontColor($r('app.color.text_muted'))
                    }
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.play_fill'))
                    .fontSize(14)
                    .fontColor([Color.White])
                }
                .width(36)
                .height(36)
                .backgroundColor($r('app.color.accent_blue'))
                .onClick(() => this.playItem(item))
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_elevated'))
              .border({ width: 0.8, color: $r('app.color.border_subtle') })
              .onClick(() => this.openDetail(item))
            }
          }, (item: MediaItem) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

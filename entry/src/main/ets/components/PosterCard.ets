import { MediaArtwork } from '../common/MediaArtwork';

@ComponentV2
export struct PosterCard {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param posterUrl: string = '';
  @Param qualityTag: string = '';
  @Param rating: number = 0;
  @Param progressRatio: number = 0; // 0..1
  @Param episodeCountLabel: string = '';
  @Param onSelect: () => void = () => {};
  /** 2in1 右键菜单里的「立即播放」 */
  @Param onPlay: () => void = () => {};

  @Local hovered: boolean = false;
  @Local imageFailed: boolean = false;

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.posterUrl && !this.imageFailed) {
          Image(MediaArtwork.resolve(this.posterUrl))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(14)
            .onError(() => {
              this.imageFailed = true;
            })

          // Subtle cinematic bottom vignette + poster typography for local artwork
          if (this.posterUrl.startsWith('local://')) {
            Column()
              .width('100%')
              .height('100%')
              .linearGradient({
                angle: 180,
                colors: [['#1A000000', 0], ['#00000000', 0.45], ['#CC090B10', 1]]
              })
              .borderRadius(14)

            Column({ space: 2 }) {
              Text(this.title.split(' (')[0])
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .maxLines(2)
                .textShadow({ radius: 6, color: '#CC000000', offsetX: 0, offsetY: 2 })
              if (this.subtitle) {
                Text(this.subtitle)
                  .fontSize(10)
                  .fontColor('#B3FFFFFF')
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, bottom: this.progressRatio > 0.01 ? 18 : 10 })
            .alignItems(HorizontalAlign.Start)
          }
        } else {
          // Graceful typographic cinema fallback poster with crisp SVG emblem
          Stack({ alignContent: Alignment.TopEnd }) {
            Image($r('app.media.art_cinema_motif'))
              .width(120)
              .height(72)
              .objectFit(ImageFit.Contain)
              .opacity(0.65)
            Column({ space: 10 }) {
              Column() {
                Image($r('app.media.ic_file_video'))
                  .width(26)
                  .height(26)
              }
              .width(46)
              .height(46)
              .borderRadius(23)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#22FFFFFF')
              .border({ width: 0.8, color: '#38FFFFFF' })
              Text(this.title.split(' (')[0])
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .maxLines(2)
                .textAlign(TextAlign.Center)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 10, right: 10 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 155,
            colors: [[MediaArtwork.paletteFor(this.title).top, 0], [MediaArtwork.paletteFor(this.title).bottom, 1]]
          })
          .borderRadius(14)
        }

        // Top badges (rating + quality/episode count)
        Row() {
          if (this.rating > 0) {
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(12)
                .fontColor([$r('app.color.accent_gold')])
              Text(this.rating.toFixed(1))
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor('#990A0B0F')
            .border({ width: 0.5, color: '#33FFFFFF' })
          }
          Blank()
          if (this.episodeCountLabel) {
            Text(this.episodeCountLabel)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .borderRadius(6)
              .backgroundColor('#CC5E8BFF')
          } else if (this.qualityTag) {
            Text(this.qualityTag.split(' · ')[0])
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.accent_cyan'))
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .borderRadius(6)
              .backgroundColor('#990A0B0F')
              .border({ width: 0.5, color: '#4438BDF8' })
          }
        }
        .width('100%')
        .padding(8)
        .position({ x: 0, y: 0 })

        // Bottom watch progress bar
        if (this.progressRatio > 0.01) {
          Column() {
            Row() {
              Row()
                .width(`${Math.min(100, Math.max(4, Math.round(this.progressRatio * 100)))}%`)
                .height(3)
                .backgroundColor($r('app.color.accent_blue'))
                .borderRadius(2)
            }
            .width('100%')
            .height(3)
            .backgroundColor('#66FFFFFF')
            .borderRadius(2)
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 8 })
        }
      }
      .width('100%')
      .aspectRatio(0.68)
      .borderRadius(14)
      .shadow({
        radius: this.hovered ? 18 : 8,
        color: this.hovered ? '#555E8BFF' : '#66000000',
        offsetX: 0,
        offsetY: 4
      })
      .border({
        width: this.hovered ? 1.5 : 0.8,
        color: this.hovered ? $r('app.color.accent_blue') : '#26FFFFFF'
      })
      .scale({ x: this.hovered ? 1.03 : 1.0, y: this.hovered ? 1.03 : 1.0 })
      .animation({ duration: 160, curve: Curve.EaseOut })
      .onHover((isHover: boolean) => {
        this.hovered = isHover;
      })

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle) {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_body_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .focusable(true)
    .onClick(() => this.onSelect())
    .bindContextMenu(this.contextMenuBuilder(), ResponseType.RightClick, {
      backgroundColor: $r('app.color.menu_bg'),
      borderRadius: 14,
      outlineColor: $r('app.color.menu_border'),
      outlineWidth: 1
    })
  }

  @Builder
  menuAction(label: string, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .height(40)
      .width('100%')
      .padding({ left: 12, right: 12 })
      .borderRadius(8)
      .onClick(action)
  }

  @Builder
  contextMenuBuilder() {
    Column({ space: 2 }) {
      this.menuAction('立即播放', () => this.onPlay())
      this.menuAction('查看详情', () => this.onSelect())
    }
    .width(148)
    .padding(6)
  }
}

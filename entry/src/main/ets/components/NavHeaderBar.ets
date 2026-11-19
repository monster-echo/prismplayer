
/** Shared pro-grade top navigation bar with standard back trigger, title/subtitle, and optional trailing action. */
@ComponentV2
export struct NavHeaderBar {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param backLabel: string = '';
  @Param rightLabel: string = '';
  @Param rightIcon: Resource | undefined = undefined;
  @Param rightAccent: boolean = false;
  @Param onBack: () => void = () => {};
  @Param onRightAction: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      if (this.backLabel) {
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor([$r('app.color.text_primary')])
            Text(this.backLabel)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
          }
        }
        .height(38)
        .padding({ left: 10, right: 12 })
        .backgroundColor($r('app.color.bg_elevated'))
        .borderRadius(19)
        .border({ width: 0.8, color: $r('app.color.fill_strong') })
        .onClick(() => this.onBack())
      } else {
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
        .onClick(() => this.onBack())
      }

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle) {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.rightLabel && this.rightIcon) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.rightIcon)
            .fontSize(16)
            .fontColor([this.rightAccent ? Color.White : $r('app.color.accent_blue')])
        }
        .width(38)
        .height(38)
        .backgroundColor(this.rightAccent ? $r('app.color.accent_blue') : '#1F5E8BFF')
        .border({ width: this.rightAccent ? 0 : 0.6, color: '#445E8BFF' })
        .onClick(() => this.onRightAction())
      } else if (this.rightLabel || this.rightIcon) {
        Button() {
          Row({ space: 5 }) {
            if (this.rightIcon) {
              SymbolGlyph(this.rightIcon)
                .fontSize(14)
                .fontColor([this.rightAccent ? Color.White : $r('app.color.accent_blue')])
            }
            if (this.rightLabel) {
              Text(this.rightLabel)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.rightAccent ? Color.White : $r('app.color.accent_blue'))
                .maxLines(1)
            }
          }
        }
        .height(36)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.rightAccent ? $r('app.color.accent_blue') : '#1F5E8BFF')
        .borderRadius(10)
        .border({ width: this.rightAccent ? 0 : 0.6, color: '#445E8BFF' })
        .onClick(() => this.onRightAction())
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 10 })
    .backgroundColor($r('app.color.bar_glass'))
    .backdropBlur(16)
    .border({ width: { bottom: 0.6 }, color: $r('app.color.fill_subtle') })
  }
}

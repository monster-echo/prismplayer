
/** Shared pro-grade top navigation bar with standard back trigger, title/subtitle, and optional trailing action. */
@ComponentV2
export struct NavHeaderBar {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param backLabel: string = '';
  @Param rightLabel: string = '';
  @Param rightIcon: Resource | undefined = undefined;
  /** 水平内边距：页面外层已自带留白时传 0，避免 header 内容比正文多缩进一圈 */
  @Param inset: number = 18;
  @Param statusLabel: string = '';
  @Param statusIcon: Resource | undefined = undefined;
  @Param statusAccent: boolean = false;
  @Param onBack: () => void = () => {};
  @Param onRightAction: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      if (this.backLabel) {
        Button() {
          Row({ space: 4 }) {
            Image($r('app.media.ic_chevron_left'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.text_primary'))
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
          Image($r('app.media.ic_chevron_left'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_primary'))
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
            .fontColor($r('app.color.text_body_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.statusLabel) {
        Row({ space: 4 }) {
          if (this.statusIcon) {
            SymbolGlyph(this.statusIcon)
              .fontSize(14)
              .fontColor([this.statusAccent ? $r('app.color.success') : $r('app.color.accent_gold')])
          }
          Text(this.statusLabel)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusAccent ? $r('app.color.success') : $r('app.color.accent_gold'))
            .maxLines(1)
        }
      } else if (!this.rightLabel && this.rightIcon) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.rightIcon)
            .fontSize(16)
            .fontColor([$r('app.color.accent_blue')])
        }
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.nav_active_bg'))
        .border({ width: 0.6, color: $r('app.color.nav_active_border') })
        .onClick(() => this.onRightAction())
      } else if (this.rightLabel || this.rightIcon) {
        Button() {
          Row({ space: 5 }) {
            if (this.rightIcon) {
              SymbolGlyph(this.rightIcon)
                .fontSize(14)
                .fontColor([$r('app.color.accent_blue')])
            }
            if (this.rightLabel) {
              Text(this.rightLabel)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent_blue'))
                .maxLines(1)
            }
          }
        }
        .height(36)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.nav_active_bg'))
        .borderRadius(10)
        .border({ width: 0.6, color: $r('app.color.nav_active_border') })
        .onClick(() => this.onRightAction())
      }
    }
    .width('100%')
    .padding({ left: this.inset, right: this.inset, top: 12, bottom: 10 })
    .backgroundColor($r('app.color.bg_primary'))
    .border({ width: { bottom: 0.6 }, color: $r('app.color.border_subtle') })
  }
}

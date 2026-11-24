import { UIContext } from '@kit.ArkUI';

export class SubtitleToast {
  static show(ui: UIContext, message: string): void {
    try {
      ui.getPromptAction().showToast({ message, duration: 1800 });
    } catch (_e) {
      // Toast is best-effort; subtitle operations must never fail because of UI messaging.
    }
  }
}

/** Consistent header for every subtitle screen: back to hub, title, close the subtitle flow. */
@ComponentV2
export struct SubtitlePageHeader {
  @Param title: string = '';
  @Param caption: string = '';
  @Param showBack: boolean = true;
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      if (this.showBack) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_chevron_left'))
            .width(16)
            .height(16)
            .fillColor(Color.White)
        }
        .width(36)
        .height(36)
        .backgroundColor('#14161D')
        .border({ width: 0.7, color: '#1FFFFFFF' })
        .onClick(() => this.onBack())
      }

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F8FAFC')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.caption) {
          Text(this.caption)
            .fontSize(11)
            .fontColor('#9CA3AF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(13)
          .fontColor(['#9CA3AF'])
      }
      .width(30)
      .height(30)
      .backgroundColor('#14161D')
      .onClick(() => this.onClose())
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 10 })
  }
}

/** Small section heading used inside a subtitle screen. */
@ComponentV2
export struct SubtitleSectionHeader {
  @Param title: string = '';
  @Param note: string = '';

  build() {
    Column({ space: 3 }) {
      Text(this.title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#E5E7EB')
      if (this.note) {
        Text(this.note)
          .fontSize(10)
          .lineHeight(15)
          .fontColor('#6B7280')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** Single-choice chip used for options such as language filtering and aspect ratios. */
@ComponentV2
export struct SubtitleChip {
  @Param label: string = '';
  @Param active: boolean = false;
  @Param interactive: boolean = true;
  @Param onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(12)
      .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.active ? Color.White : (this.interactive ? '#C7CDD8' : '#4B5563'))
      .textAlign(TextAlign.Center)
      .height(34)
      .padding({ left: 13, right: 13 })
      .borderRadius(9)
      .backgroundColor(this.active ? '#3B82F6' : '#14161D')
      .border({ width: 0.7, color: this.active ? '#3B82F6' : '#1FFFFFFF' })
      .onClick(() => {
        if (this.interactive) this.onTap();
      })
  }
}

/** Label + explanation + toggle. */
@ComponentV2
export struct SubtitleToggleRow {
  @Param title: string = '';
  @Param desc: string = '';
  @Param value: boolean = false;
  @Param interactive: boolean = true;
  @Param onChange: (value: boolean) => void = (_value: boolean) => {};

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(14)
          .fontColor(this.interactive ? Color.White : '#6B7280')
        if (this.desc) {
          Text(this.desc)
            .fontSize(10)
            .lineHeight(15)
            .fontColor('#6B7280')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .selectedColor('#3B82F6')
        .enabled(this.interactive)
        .onChange((v: boolean) => this.onChange(v))
    }
    .width('100%')
  }
}

/** Navigation row for the subtitle hub; one row opens exactly one focused screen. */
@ComponentV2
export struct SubtitleNavRow {
  @Param badge: string = '';
  @Param title: string = '';
  @Param value: string = '';
  @Param onTap: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Column() {
        Text(this.badge)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#93C5FD')
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor('#1A3B82F6')
      .justifyContent(FlexAlign.Center)

      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F8FAFC')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.value) {
        Text(this.value)
          .fontSize(11)
          .fontColor('#9CA3AF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 132 })
      }

      Image($r('app.media.ic_chevron_right'))
        .width(16)
        .height(16)
        .fillColor('#6B7280')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .onClick(() => this.onTap())
  }
}

import { PC_SHORTCUTS, ShortcutTip } from '../common/Constants';
import { PageShell } from '../components/PageShell';
import { NavHeaderBar } from '../components/NavHeaderBar';

@Entry
@ComponentV2
struct ShortcutsPage {
  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '键盘与桌面快捷键',
        subtitle: '适用于鸿蒙电脑（2in1）与平板外接键盘',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 8 }) {
                ForEach(PC_SHORTCUTS, (tip: ShortcutTip) => {
                  Row() {
                    Text(tip.keys)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor($r('app.color.bg_secondary'))
                    .border({ width: 0.6, color: $r('app.color.border_subtle') })
                    Blank()
                    Text(tip.action)
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  .borderRadius(10)
                  .backgroundColor($r('app.color.bg_elevated'))
                  .border({ width: 0.6, color: $r('app.color.border_subtle') })
                }, (tip: ShortcutTip) => tip.keys)
              }
              .padding({ left: 18, right: 18, top: 14, bottom: 32 })
              .width('100%')
            }.edgeEffect(EdgeEffect.Spring)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_primary'))
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_primary'))
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

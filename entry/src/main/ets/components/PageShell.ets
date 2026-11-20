import { BreakpointType } from '../common/Constants';
import { Layout } from '../common/Layout';
import { AppStore } from '../services/AppStore';

/**
 * 独立页面（不含侧栏）的通用窗体：只做「宽度上限 + 居中」。
 *
 * 不加任何 padding——页面自己的 padding 与 header 的内边距保持原样，
 * 手机端与改造前一致；只有窗口宽于上限时，内容才在两侧留白居中。
 */
@ComponentV2
export struct PageShell {
  /** 内容宽度上限；<=0 时按断点取内容宽度约定 */
  @Param maxWidth: number = 0;
  @BuilderParam content: () => void = this.emptyContent;
  @Local store: AppStore = AppStore.getInstance();

  @Builder
  emptyContent() {}

  private bp(): BreakpointType {
    return this.store.currentBreakpoint;
  }

  private limit(): number {
    return this.maxWidth > 0 ? this.maxWidth : Layout.contentMax(this.bp());
  }

  build() {
    Row() {
      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: this.limit() })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.bg_primary'))
  }
}

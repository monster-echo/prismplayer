import { util } from '@kit.ArkTS';
import { navTitleFor, LegalBlock, parseLegalMarkdown } from '../common/LegalMarkdown';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PageShell } from '../components/PageShell';
import { LegalDocParams } from '../common/Types';

@Entry
@ComponentV2
struct LegalDocPage {
  @Local docType: string = 'privacy';
  @Local blocks: LegalBlock[] = [];

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as LegalDocParams | undefined;
    if (params && params.docType === 'agreement') {
      this.docType = 'agreement';
    }
    this.blocks = this.loadBlocks();
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  /**
   * 协议正文随包内置（resources/rawfile/legal/*.md），不依赖网络，也不再跳浏览器。
   * 源文件在仓库 docs/legal/ 下，发布前同步到这里。
   */
  private loadBlocks(): LegalBlock[] {
    const name = this.docType === 'agreement' ? 'legal/terms.md' : 'legal/privacy.md';
    try {
      const raw = getContext(this).resourceManager.getRawFileContentSync(name);
      const text = util.TextDecoder.create('utf-8').decodeToString(raw);
      return parseLegalMarkdown(text);
    } catch (_e) {
      return [{ kind: 'p', text: '协议文本缺失，请更新到最新版本。' }];
    }
  }

  @Builder
  blockRow(block: LegalBlock) {
    if (block.kind === 'h2') {
      Text(block.text)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 18, bottom: 4 })
    } else if (block.kind === 'h3') {
      Text(block.text)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 12, bottom: 2 })
    } else if (block.kind === 'li') {
      Row({ space: 8 }) {
        Text('•')
          .fontSize(14)
          .lineHeight(23)
          .fontColor($r('app.color.text_body_muted'))
        Text(block.text)
          .fontSize(14)
          .lineHeight(23)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 2, bottom: 2 })
    } else if (block.kind === 'gap') {
      Blank().height(10)
    } else {
      Text(block.text)
        .fontSize(14)
        .lineHeight(23)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
  }

  build() {
    Column() {
      NavHeaderBar({
        title: navTitleFor(this.docType),
        subtitle: '棱镜播放器 PrismPlayer',
        onBack: () => this.getUIContext().getRouter().back()
      })

      PageShell({ maxWidth: 760 }) {
        Scroll() {
          Column({ space: 2 }) {
            ForEach(this.blocks, (b: LegalBlock, i: number) => {
              this.blockRow(b)
            }, (b: LegalBlock, i: number) => `${i}_${b.kind}`)
            Blank().height(40)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 20, right: 20, top: 12 })
        }.edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

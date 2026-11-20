const storage = new LocalStorage();

/**
 * 「继续观看」服务卡片。
 *
 * 只有三段信息：片名、进度、剩余时间提示。点整卡回到播放现场。
 * 数据全部来自 FormBindingData 注入的 LocalStorage，卡片自身不取数。
 */
@Entry(storage)
@Component
struct ContinueWatchingCard {
  @LocalStorageProp('hasData') hasData: boolean = false;
  @LocalStorageProp('title') title: string = '继续观看';
  @LocalStorageProp('detail') detail: string = '';
  @LocalStorageProp('percent') percent: number = 0;
  @LocalStorageProp('itemId') itemId: string = '';
  @LocalStorageProp('positionMs') positionMs: number = 0;

  @Builder
  progressBar() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(3)
        .backgroundColor('#33FFFFFF')
        .borderRadius(2)
      Row()
        .width(`${this.percent}%`)
        .height(3)
        .backgroundColor('#3B82F6')
        .borderRadius(2)
    }
    .width('100%')
    .height(3)
  }

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Blank()

      if (this.hasData) {
        Text(this.detail)
          .fontSize(11)
          .fontColor('#94A3B8')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      this.progressBar()
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F210131C')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          menuCode: 'card',
          itemId: this.itemId,
          positionMs: this.positionMs
        }
      });
    })
  }
}

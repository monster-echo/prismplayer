const storage = new LocalStorage();

/**
 * 「继续观看」服务卡片。
 *
 * 有海报时整卡是一张封面 + 底部压暗 + 片名与进度；没有海报时退化成深色纯文字卡。
 * 点整卡回到播放现场，数据全部来自 FormBindingData 注入，卡片自身不取数。
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
  @LocalStorageProp('hasPoster') hasPoster: boolean = false;
  @LocalStorageProp('posterUri') posterUri: string = '';

  // 卡片属性的注入晚于首次构建，封面地址必须在 build() 时求值，不能在 aboutToAppear 里缓存
  @State preferMemory: boolean = false;

  private coverSrc(): string {
    if (this.preferMemory) return this.hasPoster ? 'memory://poster' : '';
    if (this.posterUri) return this.posterUri;
    return this.hasPoster ? 'memory://poster' : '';
  }

  @Builder
  progressBar() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(3)
        .backgroundColor('#4DFFFFFF')
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
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.coverSrc()) {
        Image(this.coverSrc())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .onError(() => {
            if (!this.preferMemory) this.preferMemory = true;
          })
      }

      // 底部压暗，保证片名与进度在任何封面上都可读
      Column()
        .width('100%')
        .height('72%')
        .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 0.55], ['#F2000000', 1]] })

      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.hasData) {
          Text(this.detail)
            .fontSize(11)
            .fontColor('#C7D2E0')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        this.progressBar()
      }
      .width('100%')
      .padding(14)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F210131C')
    .borderRadius(16)
    .clip(true)
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

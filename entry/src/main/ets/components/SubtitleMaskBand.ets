import { PictureRect } from '../common/VideoLayout';

type DragMode = 'none' | 'body' | 'top' | 'bottom';

/**
 * Burned-in subtitle occlusion band: a solid black strip covering the subtitle region of
 * the video picture. Normal mode is fully pass-through (peek is driven by the page-level
 * long-press gesture); adjust mode offers drag handles on both edges.
 */
@ComponentV2
export struct SubtitleMaskBand {
  @Param peeking: boolean = false;
  @Param adjusting: boolean = false;
  @Param yTop: number = 0.78;
  @Param yBottom: number = 0.96;
  @Param picture: PictureRect = { leftVp: 0, topVp: 0, widthVp: 360, heightVp: 780 };
  @Param onChange: (yTop: number, yBottom: number) => void = (_yTop: number, _yBottom: number) => {};

  private dragMode: DragMode = 'none';
  private dragStartYTop: number = 0;
  private dragStartYBottom: number = 0;

  private get bandTopVp(): number {
    return this.picture.topVp + this.yTop * this.picture.heightVp;
  }

  private get bandHeightVp(): number {
    const raw = (this.yBottom - this.yTop) * this.picture.heightVp;
    return raw > 0 ? raw : 0;
  }

  private get minBandRatio(): number {
    return Math.min(0.5, Math.max(0.03, 28 / Math.max(120, this.picture.heightVp)));
  }

  private clampPair(yTop: number, yBottom: number): number[] {
    const minRatio = this.minBandRatio;
    let top = Math.max(0, Math.min(1 - minRatio, yTop));
    let bottom = Math.max(top + minRatio, Math.min(1, yBottom));
    if (bottom - top > 0.9) {
      if (top <= 0.1) {
        bottom = top + 0.9;
      } else {
        top = bottom - 0.9;
      }
    }
    return [top, bottom];
  }

  private handleDrag(mode: DragMode, deltaYVp: number): void {
    const deltaRatio = deltaYVp / Math.max(120, this.picture.heightVp);
    let nextTop = this.dragStartYTop;
    let nextBottom = this.dragStartYBottom;
    if (mode === 'top') {
      nextTop = this.dragStartYTop + deltaRatio;
    } else if (mode === 'bottom') {
      nextBottom = this.dragStartYBottom + deltaRatio;
    } else {
      nextTop = this.dragStartYTop + deltaRatio;
      nextBottom = this.dragStartYBottom + deltaRatio;
    }
    const pair = this.clampPair(nextTop, nextBottom);
    this.onChange(pair[0], pair[1]);
  }

  @Builder
  gripHandle(kind: DragMode) {
    Column({ space: 3 }) {
      Row({ space: 5 }) {
        ForEach(['', '', '', '', ''], (_v: string, idx: number) => {
          Column()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor('#CCFFFFFF')
        }, (idx: number) => `dot_${idx}`)
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(30)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.Default)
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 4 })
        .onActionStart(() => {
          this.dragMode = kind;
          this.dragStartYTop = this.yTop;
          this.dragStartYBottom = this.yBottom;
        })
        .onActionUpdate((ev: GestureEvent) => {
          this.handleDrag(this.dragMode, ev.offsetY);
        })
        .onActionEnd(() => {
          this.dragMode = 'none';
        })
        .onActionCancel(() => {
          this.dragMode = 'none';
        })
    )
  }

  build() {
    Stack() {
      // Mask band body
      Column() {
        if (this.adjusting) {
          Text('拖动上下边缘调整遮挡范围')
            .fontSize(11)
            .fontColor('#CCFFFFFF')
        }
      }
      .width(this.picture.widthVp)
      .height(this.bandHeightVp)
      .position({ x: this.picture.leftVp, y: this.bandTopVp })
      .backgroundColor(this.adjusting ? '#99000000' : '#FF000000')
      .borderRadius(this.adjusting ? 2 : 0)
      .border(this.adjusting ? { width: 1.2, color: '#B3FFFFFF' } : { width: 0 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(this.adjusting ? HitTestMode.Default : HitTestMode.None)
      .gesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 4 })
          .onActionStart(() => {
            this.dragMode = 'body';
            this.dragStartYTop = this.yTop;
            this.dragStartYBottom = this.yBottom;
          })
          .onActionUpdate((ev: GestureEvent) => {
            this.handleDrag(this.dragMode, ev.offsetY);
          })
          .onActionEnd(() => {
            this.dragMode = 'none';
          })
          .onActionCancel(() => {
            this.dragMode = 'none';
          })
      )

      // Adjust-mode edge handles (drawn outside the band body so they stay grabbable at extremes)
      if (this.adjusting) {
        Row() {
          this.gripHandle('top')
        }
        .width(this.picture.widthVp)
        .position({ x: this.picture.leftVp, y: this.bandTopVp - 15 })

        Row() {
          this.gripHandle('bottom')
        }
        .width(this.picture.widthVp)
        .position({ x: this.picture.leftVp, y: this.bandTopVp + this.bandHeightVp - 15 })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.adjusting ? HitTestMode.Default : HitTestMode.None)
    .opacity(this.peeking ? 0 : 1)
    .animation({ duration: 160, curve: Curve.EaseOut })
  }
}

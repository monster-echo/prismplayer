/**
 * 3x3 pattern lock. Draws dots/lines on a Canvas and reports the connected node sequence.
 * The parent decides what the pattern means; this component only captures it.
 */
@ComponentV2
export struct PatternPad {
  @Param padSize: number = 240;
  @Param onComplete: (pattern: string) => void = (_pattern: string) => {};
  @Param onInvalid: (message: string) => void = (_message: string) => {};
  /** 画线期间通知外层锁住滚动，否则手指会被 Scroll 抢走。 */
  @Param onDrawingChange: (drawing: boolean) => void = (_drawing: boolean) => {};

  @Local selected: number[] = [];
  @Local drawing: boolean = false;
  @Local cursorX: number = 0;
  @Local cursorY: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private locked: boolean = false;
  private resetTimer: number = -1;

  private nodeRadius(): number {
    return Math.max(13, this.padSize * 0.055);
  }

  private inset(): number {
    return this.padSize * 0.18;
  }

  private step(): number {
    return (this.padSize - this.inset() * 2) / 2;
  }

  private nodeX(index: number): number {
    return this.inset() + (index % 3) * this.step();
  }

  private nodeY(index: number): number {
    return this.inset() + Math.floor(index / 3) * this.step();
  }

  private draw(): void {
    const ctx = this.context;
    const r = this.nodeRadius();
    ctx.clearRect(0, 0, this.padSize, this.padSize);

    // Path lines first, so dots sit on top.
    if (this.selected.length > 0) {
      ctx.beginPath();
      ctx.lineWidth = Math.max(3, this.padSize * 0.015);
      ctx.lineCap = 'round';
      ctx.strokeStyle = '#3B82F6';
      ctx.moveTo(this.nodeX(this.selected[0]), this.nodeY(this.selected[0]));
      for (let i = 1; i < this.selected.length; i++) {
        ctx.lineTo(this.nodeX(this.selected[i]), this.nodeY(this.selected[i]));
      }
      if (this.drawing) {
        ctx.lineTo(this.cursorX, this.cursorY);
      }
      ctx.stroke();
    }

    for (let i = 0; i < 9; i++) {
      const x = this.nodeX(i);
      const y = this.nodeY(i);
      const active = this.selected.indexOf(i) >= 0;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fillStyle = active ? '#3B82F6' : '#1B2030';
      ctx.fill();
      ctx.lineWidth = active ? 2 : 1.2;
      ctx.strokeStyle = active ? '#93C5FD' : '#4B5563';
      ctx.stroke();
      if (active) {
        ctx.beginPath();
        ctx.arc(x, y, r * 0.34, 0, Math.PI * 2);
        ctx.fillStyle = '#FFFFFF';
        ctx.fill();
      }
    }
  }

  private nodeAt(x: number, y: number): number {
    const threshold = this.nodeRadius() * 1.9;
    let best = -1;
    let bestDistance = threshold * threshold;
    for (let i = 0; i < 9; i++) {
      const dx = x - this.nodeX(i);
      const dy = y - this.nodeY(i);
      const dist = dx * dx + dy * dy;
      if (dist <= bestDistance) {
        bestDistance = dist;
        best = i;
      }
    }
    return best;
  }

  private addNode(index: number): void {
    if (index < 0 || this.selected.indexOf(index) >= 0) return;
    if (this.selected.length > 0) {
      const last = this.selected[this.selected.length - 1];
      const lastRow = Math.floor(last / 3);
      const lastCol = last % 3;
      const row = Math.floor(index / 3);
      const col = index % 3;
      // Fill the midpoint when a line jumps over a dot (1 -> 3 includes 2).
      if ((lastRow + row) % 2 === 0 && (lastCol + col) % 2 === 0) {
        const mid = ((lastRow + row) / 2) * 3 + (lastCol + col) / 2;
        if (mid !== last && mid !== index && this.selected.indexOf(mid) < 0) {
          this.selected.push(mid);
        }
      }
    }
    this.selected.push(index);
  }

  private resetPattern(): void {
    this.selected = [];
    this.drawing = false;
    this.cursorX = 0;
    this.cursorY = 0;
    this.draw();
  }

  private scheduleReset(delayMs: number): void {
    this.locked = true;
    if (this.resetTimer >= 0) {
      clearTimeout(this.resetTimer);
    }
    this.resetTimer = setTimeout(() => {
      this.locked = false;
      this.resetPattern();
    }, delayMs);
  }

  private handleTouch(event: TouchEvent): void {
    if (this.locked) return;
    const touch = event.touches.length > 0 ? event.touches[0] : event.changedTouches[0];
    if (touch) {
      this.cursorX = touch.x;
      this.cursorY = touch.y;
    }
    if (event.type === TouchType.Down) {
      this.onDrawingChange(true);
      this.selected = [];
      this.drawing = true;
      if (touch) {
        const index = this.nodeAt(touch.x, touch.y);
        if (index >= 0) this.addNode(index);
      }
      this.draw();
    } else if (event.type === TouchType.Move) {
      this.drawing = true;
      if (touch) {
        const index = this.nodeAt(touch.x, touch.y);
        if (index >= 0) this.addNode(index);
      }
      this.draw();
    } else if (event.type === TouchType.Up) {
      this.drawing = false;
      this.onDrawingChange(false);
      this.draw();
      const pattern = this.selected.map((v: number) => `${v + 1}`).join('');
      if (pattern.length < 4) {
        this.onInvalid('至少连接 4 个点');
        this.scheduleReset(500);
        return;
      }
      this.onComplete(pattern);
      this.scheduleReset(450);
    } else if (event.type === TouchType.Cancel) {
      this.drawing = false;
      this.onDrawingChange(false);
      this.resetPattern();
    }
  }

  build() {
    Canvas(this.context)
      .width(this.padSize)
      .height(this.padSize)
      .onReady(() => this.draw())
      .onTouch((event: TouchEvent) => this.handleTouch(event))
  }
}

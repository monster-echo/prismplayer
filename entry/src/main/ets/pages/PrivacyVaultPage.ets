import { VaultEntry } from '../common/Types';
import { PageShell } from '../components/PageShell';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PatternPad } from '../components/PatternPad';
import { AppStore } from '../services/AppStore';

type ChangeStage = 'old' | 'new' | 'confirm';

@Entry
@ComponentV2
struct PrivacyVaultPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local firstPattern: string = '';
  @Local statusText: string = '';
  @Local isError: boolean = false;
  @Local showChangePattern: boolean = false;
  @Local changeStage: ChangeStage = 'old';
  @Local newPattern: string = '';
  @Local busy: boolean = false;

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private getSourceName(sourceId: string): string {
    const src = this.store.sources.find(s => s.id === sourceId);
    return src ? src.name : sourceId;
  }

  private setupPrompt(): string {
    if (this.firstPattern) return '再次绘制确认';
    return '绘制解锁图案';
  }

  private changePrompt(): string {
    if (this.changeStage === 'old') return '绘制当前图案';
    if (this.changeStage === 'new') return '绘制新图案';
    return '再次绘制新图案';
  }

  private showStatus(message: string, error: boolean): void {
    this.statusText = message;
    this.isError = error;
  }

  private async onPattern(pattern: string): Promise<void> {
    if (this.busy) return;

    if (!this.store.hasVaultPattern()) {
      if (!this.firstPattern) {
        this.firstPattern = pattern;
        this.statusText = '';
        return;
      }
      if (pattern !== this.firstPattern) {
        this.firstPattern = '';
        this.showStatus('两次图案不一致，请重画', true);
        return;
      }
      this.busy = true;
      await this.store.setVaultPattern(pattern);
      await this.store.unlockVault(pattern);
      this.busy = false;
      this.firstPattern = '';
      this.statusText = '';
      return;
    }

    if (!this.store.vaultUnlocked) {
      this.busy = true;
      const ok = await this.store.unlockVault(pattern);
      this.busy = false;
      if (!ok) this.showStatus('图案错误', true);
      return;
    }

    if (!this.showChangePattern) return;

    if (this.changeStage === 'old') {
      this.busy = true;
      const ok = await this.store.verifyVaultPattern(pattern);
      this.busy = false;
      if (!ok) {
        this.showStatus('当前图案错误', true);
        return;
      }
      this.changeStage = 'new';
      this.statusText = '';
      return;
    }

    if (this.changeStage === 'new') {
      this.newPattern = pattern;
      this.changeStage = 'confirm';
      this.statusText = '';
      return;
    }

    if (pattern !== this.newPattern) {
      this.changeStage = 'new';
      this.newPattern = '';
      this.showStatus('两次图案不一致，请重画', true);
      return;
    }

    this.busy = true;
    await this.store.setVaultPattern(pattern);
    this.busy = false;
    this.showChangePattern = false;
    this.changeStage = 'old';
    this.newPattern = '';
    this.statusText = '';
  }

  private toggleChangePattern(): void {
    this.showChangePattern = !this.showChangePattern;
    this.changeStage = 'old';
    this.newPattern = '';
    this.statusText = '';
    this.isError = false;
  }

  @Builder
  patternCard(prompt: string) {
    Column({ space: 10 }) {
      Text(prompt)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_secondary'))
      PatternPad({
        padSize: 250,
        onComplete: (pattern: string) => { this.onPattern(pattern); },
        onInvalid: (message: string) => { this.showStatus(message, true); }
      })
      if (this.statusText) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.isError ? $r('app.color.danger') : $r('app.color.success'))
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .borderRadius(14)
    .backgroundColor($r('app.color.bg_elevated'))
    .border({ width: 0.8, color: $r('app.color.border_subtle') })
  }

  @Builder
  vaultEntryRow(entry: VaultEntry) {
    Row({ space: 12 }) {
      if (entry.kind === 'folder') {
        Column() {
          Image($r('app.media.ic_file_folder')).width(24).height(24)
        }
        .width(44)
        .height(62)
        .borderRadius(6)
        .backgroundColor($r('app.color.fill_subtle'))
        .justifyContent(FlexAlign.Center)
      } else if (entry.posterUrl) {
        Image(entry.posterUrl)
          .width(44)
          .height(62)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.fill_subtle'))
      } else {
        Column() {
          Image($r('app.media.ic_file_video')).width(22).height(22)
        }
        .width(44)
        .height(62)
        .borderRadius(6)
        .backgroundColor($r('app.color.fill_subtle'))
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: 2 }) {
        Text(entry.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${entry.kind === 'series' ? '剧集' : entry.kind === 'movie' ? '电影' : '目录'} · ${this.getSourceName(entry.sourceId)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_body_muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Button('取消隐藏')
        .height(30)
        .padding({ left: 10, right: 10 })
        .fontSize(11)
        .fontColor($r('app.color.danger'))
        .backgroundColor('#1AF87171')
        .borderRadius(8)
        .onClick(() => { this.store.unhideVaultEntry(entry); })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.bg_elevated'))
    .border({ width: 0.7, color: '#22FFFFFF' })
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '隐私保险库',
        subtitle: `已隐藏 ${this.store.vaultEntries.length} 项`,
        statusLabel: this.store.vaultUnlocked ? '已解锁' : (this.store.hasVaultPattern() ? '已锁定' : '未设置'),
        statusIcon: this.store.vaultUnlocked ? $r('sys.symbol.lock_open_fill') : $r('sys.symbol.lock_fill'),
        statusAccent: this.store.vaultUnlocked,
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          if (!this.store.hasVaultPattern() || !this.store.vaultUnlocked) {
            // 解锁/设置图案是固定操作区，不跟随页面滚动
            Column() {
              this.patternCard(this.store.hasVaultPattern() ? '绘制图案解锁' : this.setupPrompt())
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ left: 18, right: 18, bottom: 32 })
          } else {
            Column({ space: 12 }) {
              Row({ space: 10 }) {
                Button('立即上锁')
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.Black)
                  .backgroundColor($r('app.color.accent_gold'))
                  .borderRadius(10)
                  .onClick(() => {
                    this.store.lockVault();
                    this.showChangePattern = false;
                    this.statusText = '';
                  })

                Button(this.showChangePattern ? '收起' : '修改图案')
                  .height(42)
                  .padding({ left: 16, right: 16 })
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_elevated'))
                  .borderRadius(10)
                  .border({ width: 0.7, color: $r('app.color.fill_strong') })
                  .onClick(() => this.toggleChangePattern())
              }
              .width('100%')

              if (this.showChangePattern) {
                this.patternCard(this.changePrompt())
              }

              Row() {
                Text(`已隐藏内容 (${this.store.vaultEntries.length})`)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))
                Blank()
              }
              .width('100%')

              if (this.store.vaultEntries.length === 0) {
                Text('暂无隐藏内容')
                  .fontSize(12)
                  .fontColor($r('app.color.text_body_muted'))
              } else {
                List({ space: 8 }) {
                  ForEach(this.store.vaultEntries, (entry: VaultEntry) => {
                    ListItem() {
                      this.vaultEntryRow(entry)
                    }
                  }, (e: VaultEntry) => e.id)
                }
                .layoutWeight(1)
                .width('100%')
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
              }

              Text('隐藏不会修改原文件。')
                .fontSize(11)
                .fontColor($r('app.color.text_body_muted'))
            }
            .width('100%')
            .height('100%')
            .padding({ left: 18, right: 18, top: 14, bottom: 24 })
            .alignItems(HorizontalAlign.Start)
          }
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

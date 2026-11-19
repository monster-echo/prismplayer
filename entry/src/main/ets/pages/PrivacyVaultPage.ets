import { VaultEntry } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';

@Entry
@ComponentV2
struct PrivacyVaultPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local pinInput: string = '';
  @Local confirmPinInput: string = '';
  @Local oldPinInput: string = '';
  @Local showChangePin: boolean = false;
  @Local statusText: string = '';
  @Local isError: boolean = false;

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private getSourceName(sourceId: string): string {
    const src = this.store.sources.find(s => s.id === sourceId);
    return src ? src.name : sourceId;
  }

  private async handleSetupOrUnlock(): Promise<void> {
    if (!this.store.hasVaultPin()) {
      const p1 = this.pinInput.trim();
      const p2 = this.confirmPinInput.trim();
      if (p1.length < 4) {
        this.isError = true;
        this.statusText = '请设置至少 4 位数字密码';
        return;
      }
      if (p1 !== p2) {
        this.isError = true;
        this.statusText = '两次输入的密码不一致';
        return;
      }
      await this.store.setVaultPin(p1);
      await this.store.unlockVault(p1);
      this.pinInput = '';
      this.confirmPinInput = '';
      this.isError = false;
      this.statusText = '保险箱密码已设定并已解锁，可在片源目录或详情页把内容隐藏到保险库';
      return;
    }

    const ok = await this.store.unlockVault(this.pinInput);
    if (ok) {
      this.pinInput = '';
      this.isError = false;
      this.statusText = '已解锁隐藏内容，切换至后台将自动重新上锁';
    } else {
      this.isError = true;
      this.statusText = '保险箱密码错误，请重试';
    }
  }

  private async handleUpdatePin(): Promise<void> {
    const valid = await this.store.verifyVaultPin(this.oldPinInput);
    if (!valid) {
      this.isError = true;
      this.statusText = '原密码验证失败';
      return;
    }
    const next = this.pinInput.trim();
    if (next.length < 4) {
      this.isError = true;
      this.statusText = '新密码至少 4 位';
      return;
    }
    await this.store.setVaultPin(next);
    this.oldPinInput = '';
    this.pinInput = '';
    this.showChangePin = false;
    this.isError = false;
    this.statusText = '私密保险箱密码已更新';
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '隐私保险库',
        subtitle: this.store.vaultUnlocked
          ? '当前状态：已解锁（退回后台自动上锁）'
          : (this.store.hasVaultPin() ? '当前状态：已加锁保护中' : '首次使用请设置 4 位以上安全密码'),
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 18 }) {
          // Status Hero Card
          Row({ space: 14 }) {
            Column() {
              Image($r('app.media.ic_lock_vault')).width(30).height(30)
            }
            .width(50)
            .height(50)
            .borderRadius(13)
            .backgroundColor(this.store.vaultUnlocked ? '#2234D399' : '#24F5B841')
            .justifyContent(FlexAlign.Center)

            Column({ space: 4 }) {
              Text(this.store.vaultUnlocked ? '私密空间已解锁' : '保险库保护中')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text(
                this.store.vaultUnlocked
                  ? `已隐藏 ${this.store.vaultEntries.length} 项内容 · 现在可在影库中查看`
                  : `已隐藏 ${this.store.vaultEntries.length} 项剧集 / 电影 / 目录及其观看记录`
              )
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: this.store.vaultUnlocked ? '#4434D399' : '#44F5B841' })

          if (!this.store.hasVaultPin() || !this.store.vaultUnlocked) {
            Column({ space: 12 }) {
              Text(this.store.hasVaultPin() ? '输入保险箱密码解锁隐藏内容' : '设置保险箱访问密码（HUKS 加密存储）')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))

              TextInput({ text: this.pinInput, placeholder: '输入 4-8 位数字密码' })
                .type(InputType.Password)
                .height(44)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.bg_secondary'))
                .borderRadius(10)
                .onChange((v: string) => { this.pinInput = v; })

              if (!this.store.hasVaultPin()) {
                TextInput({ text: this.confirmPinInput, placeholder: '再次确认密码' })
                  .type(InputType.Password)
                  .height(44)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onChange((v: string) => { this.confirmPinInput = v; })
              }

              Button(this.store.hasVaultPin() ? '验证并解锁' : '保存密码并开启保险库')
                .width('100%')
                .height(44)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .backgroundColor($r('app.color.accent_blue'))
                .borderRadius(10)
                .onClick(() => { this.handleSetupOrUnlock(); })
            }
            .width('100%')
            .padding(16)
            .borderRadius(14)
            .backgroundColor($r('app.color.bg_elevated'))
            .border({ width: 0.8, color: $r('app.color.border_subtle') })
            .alignItems(HorizontalAlign.Start)
          } else {
            // Unlocked Vault Controls + Hidden Folder List
            Row({ space: 10 }) {
              Button('立即上锁并隐藏')
                .layoutWeight(1)
                .height(42)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.Black)
                .backgroundColor($r('app.color.accent_gold'))
                .borderRadius(10)
                .onClick(() => {
                  this.store.lockVault();
                  this.isError = false;
                  this.statusText = '已立即上锁，全部隐藏内容已重新保护';
                })

              Button(this.showChangePin ? '收起改密' : '修改密码')
                .height(42)
                .padding({ left: 16, right: 16 })
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.bg_elevated'))
                .borderRadius(10)
                .border({ width: 0.7, color: $r('app.color.fill_strong') })
                .onClick(() => { this.showChangePin = !this.showChangePin; })
            }
            .width('100%')

            if (this.showChangePin) {
              Column({ space: 10 }) {
                TextInput({ text: this.oldPinInput, placeholder: '输入当前密码' })
                  .type(InputType.Password)
                  .height(42)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onChange((v: string) => { this.oldPinInput = v; })

                TextInput({ text: this.pinInput, placeholder: '输入新密码（至少 4 位）' })
                  .type(InputType.Password)
                  .height(42)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onChange((v: string) => { this.pinInput = v; })

                Button('确认修改密码')
                  .width('100%')
                  .height(40)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.accent_blue'))
                  .borderRadius(10)
                  .onClick(() => { this.handleUpdatePin(); })
              }
              .width('100%')
              .padding(14)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_elevated'))
              .border({ width: 0.8, color: $r('app.color.border_subtle') })
            }

            Column({ space: 10 }) {
              Text(`已隐藏内容 (${this.store.vaultEntries.length})`)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))

              if (this.store.vaultEntries.length === 0) {
                Text('暂未隐藏任何内容。可在剧集 / 电影详情页点「隐藏到保险库」，或在「片源 → 浏览目录」隐藏整个目录。')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_muted'))
              } else {
                ForEach(this.store.vaultEntries, (entry: VaultEntry) => {
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
                        .fontColor($r('app.color.text_muted'))
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
                }, (e: VaultEntry) => e.id)
              }

              Text('说明：隐藏只是把内容从影库与搜索中移出并由保险箱密码保护，服务器上的原始文件不会被加密或修改。')
                .fontSize(10)
                .lineHeight(16)
                .fontColor($r('app.color.text_muted'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if (this.statusText) {
            Text(this.statusText)
              .fontSize(12)
              .lineHeight(18)
              .fontColor(this.isError ? $r('app.color.danger') : $r('app.color.success'))
              .padding(12)
              .width('100%')
              .borderRadius(10)
              .backgroundColor($r('app.color.bg_elevated'))
          }
        }
        .padding({ left: 18, right: 18, top: 14, bottom: 32 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants, BreakpointType } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { Layout } from '../common/Layout';
import { AppStore } from '../services/AppStore';
import { LocalStorageUsage, LocalStorageUsageInfo } from '../services/LocalStorageUsage';
import { ThemeMode } from '../common/Types';

@ComponentV2
export struct SettingsView {
  @Param breakpoint: BreakpointType = 'sm';
  @Param onOpenDecoderPrefs: () => void = () => {};
  @Param onOpenCachePrefs: () => void = () => {};
  @Param onOpenSubtitlePrefs: () => void = () => {};
  @Param onOpenShortcuts: () => void = () => {};
  @Param onOpenTmdbConfig: () => void = () => {};
  @Param onOpenPrivacyVault: () => void = () => {};
  @Param onOpenAboutPrivacy: () => void = () => {};
  @Param onOpenPrivacyPolicy: () => void = () => {};
  @Param onOpenUserAgreement: () => void = () => {};
  @Param onRequestPro: () => void = () => {};

  @Local store: AppStore = AppStore.getInstance();
  @Local showGroupQr: boolean = false;
  @Local storageUsage: LocalStorageUsageInfo = new LocalStorageUsageInfo();
  @Local storageLoaded: boolean = false;

  aboutToAppear(): void {
    this.refreshStorageUsage();
  }

  private async refreshStorageUsage(): Promise<void> {
    hilog.info(0x0001, 'PrismStorage', 'refresh start');
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const usage = await LocalStorageUsage.collect(ctx);
      this.storageUsage.appBytes = usage.appBytes;
      this.storageUsage.cacheBytes = usage.cacheBytes;
      this.storageUsage.freeBytes = usage.freeBytes;
      this.storageUsage.totalBytes = usage.totalBytes;
      this.storageLoaded = true;
      hilog.info(0x0001, 'PrismStorage',
        'usage app=%{public}d cache=%{public}d free=%{public}d total=%{public}d',
        usage.appBytes, usage.cacheBytes, usage.freeBytes, usage.totalBytes);
    } catch (e) {
      this.storageLoaded = false;
      hilog.error(0x0001, 'PrismStorage', 'refresh failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private canClearStorage(): boolean {
    return this.storageLoaded && this.storageUsage.cacheBytes > 0;
  }

  private confirmClearStorage(): void {
    const u = this.storageUsage;
    this.getUIContext().showAlertDialog({
      title: '清空缓存',
      message: `将删除 ${Formatters.formatBytes(u.cacheBytes)} 缓存（封面、字幕、分享图），不影响影库和本机文件。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认清空',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.clearStorage();
        }
      }
    });
  }

  private async clearStorage(): Promise<void> {
    try {
      const freed = await this.store.clearCache();
      await this.refreshStorageUsage();
      promptAction.showToast({ message: `已清空，释放 ${Formatters.formatBytes(freed)}` });
    } catch (e) {
      hilog.error(0x0001, 'PrismStorage', 'clear failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      promptAction.showToast({ message: '清空失败，请重试' });
    }
  }

  /** 带品牌图分享：先落一张 card.png 到缓存，再连同文案一起交给系统分享面板。 */
  private async shareApp(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const raw = ctx.resourceManager.getRawFileContentSync('share/card.png');
      const path = `${ctx.cacheDir}/prism-share-card.png`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, raw.buffer);
      fs.closeSync(file);
      const data = new systemShare.SharedData({
        utd: 'general.png',
        uri: fileUri.getUriFromPath(path),
        title: '棱镜播放器 PrismPlayer'
      });
      data.addRecord({
        utd: 'general.plain-text',
        content: '棱镜播放器 · 直连 NAS / WebDAV / 私有云\nhttps://appgallery.huawei.com/app/detail?id=tech.zhongbei.prismplayer'
      });
      await new systemShare.ShareController(data).show(ctx, {});
    } catch (_e) {
      promptAction.showToast({ message: '当前设备不支持系统分享' });
    }
  }

  /**
   * 装了飞书就直接进群，没装就出二维码。
   * 先用 canOpenLink 判断，避免 startAbility 触发系统「暂无可用打开方式」弹窗。
   */
  private openGroup(): void {
    let canOpen = false;
    try {
      canOpen = bundleManager.canOpenLink(AppConstants.FEISHU_GROUP_URL);
    } catch (_e) {
      canOpen = false;
    }
    if (!canOpen) {
      this.showGroupQr = true;
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.startAbility({
      action: 'ohos.want.action.viewData',
      uri: AppConstants.FEISHU_GROUP_URL
    }).catch(() => {
      this.showGroupQr = true;
    });
  }

  /** 打开应用市场的详情页，用户可在页面内评分。 */
  private openStorePage(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.startAbility({
      action: 'ohos.want.action.viewData',
      uri: 'store://appgallery.huawei.com/app/detail?id=tech.zhongbei.prismplayer'
    }).catch(() => {
      promptAction.showToast({ message: '未找到应用市场，请先安装并打开本应用后再评分' });
    });
  }

  themeOptionLabel(mode: ThemeMode): string {
    return mode === 'light' ? '浅色' : mode === 'dark' ? '深色' : '跟随系统';
  }

  @Builder
  themeOption(mode: ThemeMode, label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.store.settings.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.store.settings.themeMode === mode ? Color.White : $r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .borderRadius(9)
      .backgroundColor(this.store.settings.themeMode === mode ? $r('app.color.accent_blue') : $r('app.color.fill_subtle'))
      .onClick(() => {
        if (this.store.settings.themeMode !== mode) {
          this.store.setThemeMode(mode).catch(() => {});
        }
      })
  }

  @Builder
  settingNavRow(icon: Resource, title: string, valueText: string, onTap: () => void) {
    Row({ space: 12 }) {
      Column() {
        Image(icon).width(22).height(22)
      }
      .width(36)
      .height(36)
      .borderRadius(9)
      .backgroundColor($r('app.color.fill_subtle'))
      .justifyContent(FlexAlign.Center)

      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (valueText) {
        Text(valueText)
          .fontSize(12)
          .fontColor($r('app.color.text_body_muted'))
          .maxLines(1)
      }

      Image($r('app.media.ic_chevron_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_muted'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .onClick(() => onTap())
  }

  @Builder
  settingSymbolRow(symbol: Resource, color: ResourceColor, title: string, valueText: string, onTap: () => void) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph(symbol).fontSize(20).fontColor([color])
      }
      .width(36)
      .height(36)
      .borderRadius(9)
      .backgroundColor($r('app.color.fill_subtle'))
      .justifyContent(FlexAlign.Center)

      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .layoutWeight(1)

      if (valueText) {
        Text(valueText)
          .fontSize(12)
          .fontColor($r('app.color.text_body_muted'))
          .maxLines(1)
      }

      Image($r('app.media.ic_chevron_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_muted'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .onClick(() => onTap())
  }

  @Builder
  groupQrSheet() {
    Column({ space: 14 }) {
      Image($r('app.media.qr_group'))
        .width(240)
        .height(240)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
      Text('扫码加入棱镜播放器官方社群')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 20, bottom: 28 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Row({ space: 10 }) {
          Image($r('app.media.ic_brand_prism')).width(26).height(26)
          Text('设置')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
        }.width('100%')

        // Group 0: Pro（放最上面，与「设置与 Pro」的入口命名对应）
        Column({ space: 6 }) {
          Column() {
            this.settingNavRow(
              $r('app.media.ic_pro_crown'),
              'PrismPlayer Pro',
              this.store.isPro ? '已激活' : '未激活',
              () => this.onRequestPro()
            )
          }
          .width('100%')
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // Group 0.5: Appearance
        Column({ space: 6 }) {
          Text('外观')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body_muted'))
            .padding({ left: 4 })

          Column() {
            Row({ space: 12 }) {
              Text('主题')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(this.themeOptionLabel(this.store.settings.themeMode))
                .fontSize(12)
                .fontColor($r('app.color.text_body_muted'))
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })

            Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })

            Row({ space: 8 }) {
              this.themeOption('system', '跟随系统')
              this.themeOption('light', '浅色')
              this.themeOption('dark', '深色')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          }
          .width('100%')
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // Group 1: Playback, Cache, Subtitles & Metadata (Single-Purpose Pages)
        Column({ space: 6 }) {
          Text('播放与影库')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body_muted'))
            .padding({ left: 4 })

          Column() {
            this.settingNavRow(
              $r('app.media.ic_codec_hw'),
              '视频解码与硬解路由',
              this.store.settings.preferHardwareDecode ? '优先硬解' : 'FFmpeg 软解',
              () => this.onOpenDecoderPrefs()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_cache_proxy'),
              '网络预读与缓存',
              `${this.store.settings.cacheBudgetMb} MB`,
              () => this.onOpenCachePrefs()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_file_subtitle'),
              '字幕默认样式',
              `${this.store.settings.subtitleFontSizeFp} fp`,
              () => this.onOpenSubtitlePrefs()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_tmdb_clapboard'),
              'TMDB 海报墙刮削',
              this.store.settings.tmdbApiKey ? 'Key 已配置' : '公开元数据 / NFO',
              () => this.onOpenTmdbConfig()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_keyboard_pc'),
              '键盘与桌面快捷键',
              '11 项',
              () => this.onOpenShortcuts()
            )
          }
          .width('100%')
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // Group 1.5: 本地存储占用（只读统计）
        Column({ space: 6 }) {
          Row() {
            Text('存储')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_body_muted'))

            Blank()

            if (this.canClearStorage()) {
              Text('清空')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.danger'))
                .padding({ left: 12, top: 4, bottom: 4 })
                .onClick(() => this.confirmClearStorage())
            }
          }
          .width('100%')
          .padding({ left: 4, right: 4 })

          Column() {
            Row({ space: 12 }) {
              Text('本应用占用')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(this.storageLoaded ? Formatters.formatBytes(this.storageUsage.appBytes) : '—')
                .fontSize(13)
                .fontColor($r('app.color.text_body_muted'))
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })


            Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })

            Row({ space: 12 }) {
              Text('缓存')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(this.storageLoaded ? Formatters.formatBytes(this.storageUsage.cacheBytes) : '—')
                .fontSize(13)
                .fontColor($r('app.color.text_body_muted'))
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })

            Divider().color($r('app.color.divider')).margin({ left: 14, right: 14 })

            Row({ space: 12 }) {
              Text('设备可用空间')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(this.storageLoaded && this.storageUsage.totalBytes > 0
                ? `${Formatters.formatBytes(this.storageUsage.freeBytes)} / ${Formatters.formatBytes(this.storageUsage.totalBytes)}`
                : '—')
                .fontSize(13)
                .fontColor($r('app.color.text_body_muted'))
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          }
          .width('100%')
          .borderRadius(12)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // Group 2: Security, Diagnostics & Open-Source
        Column({ space: 6 }) {
          Text('安全、诊断与合规')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_body_muted'))
            .padding({ left: 4 })

          Column() {
            this.settingNavRow(
              $r('app.media.ic_lock_vault'),
              '私密文件夹隐藏',
              this.store.hiddenFolders.length > 0
                ? (this.store.vaultUnlocked ? `已解锁 · ${this.store.hiddenFolders.length} 目录` : `已保护 ${this.store.hiddenFolders.length} 目录`)
                : (this.store.hasVaultPattern() ? '已设图案' : '未启用'),
              () => this.onOpenPrivacyVault()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_shield_vault'),
              '隐私政策',
              '已更新',
              () => this.onOpenPrivacyPolicy()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_lock_vault'),
              '用户服务协议',
              '',
              () => this.onOpenUserAgreement()
            )
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingNavRow(
              $r('app.media.ic_shield_vault'),
              '隐私安全与开源许可',
              this.store.proxyPort > 0 ? `Port ${this.store.proxyPort}` : 'HUKS AES-256',
              () => this.onOpenAboutPrivacy()
            )
          }
          .width('100%')
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // Group 3: 联系与分享
        Column({ space: 6 }) {
          Text('联系与分享')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_body_muted'))
            .padding({ left: 4 })

          Column() {
            this.settingSymbolRow($r('sys.symbol.qrcode'), $r('app.color.accent_cyan'), '官方社群', '飞书 / 扫码', () => {
              this.openGroup();
            })
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingSymbolRow($r('sys.symbol.share'), $r('app.color.accent_blue'), '分享给朋友', '', () => {
              this.shareApp();
            })
            Divider().color($r('app.color.divider')).margin({ left: 62 })
            this.settingSymbolRow($r('sys.symbol.star_fill'), $r('app.color.accent_gold'), '给个五星好评', '', () => {
              this.openStorePage();
            })
          }
          .width('100%')
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .padding({
        left: Layout.gutter(this.breakpoint),
        right: Layout.gutter(this.breakpoint),
        top: 16,
        bottom: 32
      })
      .width('100%')
      .constraintSize({ maxWidth: Layout.readingMax(this.breakpoint) + Layout.gutter(this.breakpoint) * 2 })
    }.edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor($r('app.color.bg_primary'))
    .scrollBar(BarState.Off)
    .bindSheet(this.showGroupQr, this.groupQrSheet(), {
      height: 420,
      dragBar: true,
      showClose: true,
      title: { title: '官方社群' },
      backgroundColor: $r('app.color.bg_elevated'),
      onDisappear: () => { this.showGroupQr = false; }
    })
  }
}

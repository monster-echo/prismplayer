import { AppStore } from '../services/AppStore';
import { ThemeMode } from '../common/Types';

@ComponentV2
export struct SettingsView {
  @Param onOpenDecoderPrefs: () => void = () => {};
  @Param onOpenCachePrefs: () => void = () => {};
  @Param onOpenSubtitlePrefs: () => void = () => {};
  @Param onOpenShortcuts: () => void = () => {};
  @Param onOpenTmdbConfig: () => void = () => {};
  @Param onOpenPrivacyVault: () => void = () => {};
  @Param onOpenAboutPrivacy: () => void = () => {};
  @Param onOpenPrivacyPolicy: () => void = () => {};
  @Param onOpenUserAgreement: () => void = () => {};

  @Local store: AppStore = AppStore.getInstance();

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
          .fontColor($r('app.color.text_muted'))
          .maxLines(1)
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_muted')])
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .onClick(() => onTap())
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

        // Group 0: Appearance
        Column({ space: 6 }) {
          Text('外观')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_muted'))
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
                .fontColor($r('app.color.text_muted'))
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
            .fontColor($r('app.color.text_muted'))
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

        // Group 2: Security, Diagnostics & Open-Source
        Column({ space: 6 }) {
          Text('安全、诊断与合规')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_muted'))
            .padding({ left: 4 })

          Column() {
            this.settingNavRow(
              $r('app.media.ic_lock_vault'),
              '私密文件夹隐藏',
              this.store.hiddenFolders.length > 0
                ? (this.store.vaultUnlocked ? `已解锁 · ${this.store.hiddenFolders.length} 目录` : `已保护 ${this.store.hiddenFolders.length} 目录`)
                : (this.store.hasVaultPin() ? '已设密码' : '未启用'),
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
      }
      .padding({ left: 20, right: 20, top: 16, bottom: 32 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .backgroundColor($r('app.color.bg_primary'))
    .scrollBar(BarState.Off)
  }
}

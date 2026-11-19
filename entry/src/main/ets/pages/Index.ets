import { common } from '@kit.AbilityKit';
import {
  LegalDocParams,
  MediaDetailParams,
  MediaItem,
  MediaSource,
  PlayerLaunchParams,
  SeriesGroup,
  SourceBrowserParams,
  SourceFormParams
} from '../common/Types';
import { PrivacyConsentDialog } from '../components/PrivacyConsentDialog';
import { AppStore } from '../services/AppStore';
import { HistoryView } from './HistoryView';
import { LibraryView } from './LibraryView';
import { SettingsView } from './SettingsView';
import { SourcesView } from './SourcesView';

@Entry
@ComponentV2
struct Index {
  @Local store: AppStore = AppStore.getInstance();
  @Local activeTab: number = 0;
  @Local sidebarCollapsed: boolean = false;

  onPageShow(): void {
    if (this.store.pendingLaunchItem && this.store.privacyAccepted) {
      const target = this.store.pendingLaunchItem;
      this.store.pendingLaunchItem = null;
      this.launchPlayer(target, 0);
    }
  }

  private pushRoute(url: string, params?: Object): void {
    this.getUIContext().getRouter().pushUrl({ url, params });
  }

  private openLegalDoc(docType: string): void {
    this.pushRoute('pages/LegalDocPage', { docType } as LegalDocParams);
  }

  private launchPlayer(item: MediaItem, startPosMs: number): void {
    const src = this.store.sources.find(s => s.id === item.sourceId);
    const params: PlayerLaunchParams = {
      item,
      source: src,
      startPositionMs: startPosMs
    };
    this.pushRoute('pages/PlayerPage', params);
  }

  private openMovieDetail(item: MediaItem): void {
    const params: MediaDetailParams = { movie: item };
    this.pushRoute('pages/MediaDetailPage', params);
  }

  private openSeriesDetail(series: SeriesGroup): void {
    const params: MediaDetailParams = { series };
    this.pushRoute('pages/MediaDetailPage', params);
  }

  private openSourceForm(editing: MediaSource | null): void {
    const params: SourceFormParams = { editingSource: editing ?? undefined };
    this.pushRoute('pages/SourceFormPage', params);
  }

  private openSourceBrowser(source: MediaSource): void {
    const params: SourceBrowserParams = {
      source,
      initialPath: source.rootPath || '/'
    };
    this.pushRoute('pages/SourceBrowserPage', params);
  }

  private isDesktopOrTablet(): boolean {
    return this.store.currentBreakpoint !== 'sm' || this.store.isLandscape;
  }

  private tabSymbol(index: number, active: boolean): Resource {
    if (index === 0) return active ? $r('sys.symbol.movie_fill') : $r('sys.symbol.movie');
    if (index === 1) return active ? $r('sys.symbol.externaldrive_fill') : $r('sys.symbol.externaldrive');
    if (index === 2) return $r('sys.symbol.arrow_counterclockwise_clock');
    return active ? $r('sys.symbol.gearshape_fill') : $r('sys.symbol.gearshape');
  }

  @Builder
  navItem(index: number, label: string) {
    Row({ space: 12 }) {
      SymbolGlyph(this.tabSymbol(index, this.activeTab === index))
        .fontSize(18)
        .fontColor([this.activeTab === index ? $r('app.color.accent_blue') : $r('app.color.text_secondary')])
      if (!this.sidebarCollapsed) {
        Text(label)
          .fontSize(14)
          .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.activeTab === index ? Color.White : $r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .borderRadius(12)
    .backgroundColor(this.activeTab === index ? '#245E8BFF' : Color.Transparent)
    .border({ width: this.activeTab === index ? 0.6 : 0, color: '#445E8BFF' })
    .justifyContent(this.sidebarCollapsed ? FlexAlign.Center : FlexAlign.Start)
    .onClick(() => {
      this.activeTab = index;
    })
  }

  @Builder
  bottomTabBtn(index: number, label: string) {
    Column({ space: 4 }) {
      SymbolGlyph(this.tabSymbol(index, this.activeTab === index))
        .fontSize(20)
        .fontColor([this.activeTab === index ? $r('app.color.accent_blue') : $r('app.color.text_muted')])
      Text(label)
        .fontSize(10)
        .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === index ? $r('app.color.accent_blue') : $r('app.color.text_muted'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.activeTab = index;
    })
  }

  @Builder
  activeContentView() {
    if (this.activeTab === 0) {
      LibraryView({
        breakpoint: this.store.currentBreakpoint,
        onOpenMovie: (item: MediaItem) => this.openMovieDetail(item),
        onOpenSeries: (grp: SeriesGroup) => this.openSeriesDetail(grp),
        onPlayDirect: (item: MediaItem, startPosMs: number) => this.launchPlayer(item, startPosMs),
        onGoSources: () => { this.activeTab = 1; },
        onOpenSearch: () => this.pushRoute('pages/SearchPage'),
        onOpenVault: () => this.pushRoute('pages/PrivacyVaultPage')
      })
    } else if (this.activeTab === 1) {
      SourcesView({
        breakpoint: this.store.currentBreakpoint,
        onOpenEditor: (editing: MediaSource | null) => this.openSourceForm(editing),
        onBrowseSource: (src: MediaSource) => this.openSourceBrowser(src),
        onRequestPro: () => this.pushRoute('pages/ProStorePage'),
        onPlayItem: (item: MediaItem, startPosMs: number) => this.launchPlayer(item, startPosMs)
      })
    } else if (this.activeTab === 2) {
      HistoryView({
        onPlayItem: (item: MediaItem, startPosMs: number) => this.launchPlayer(item, startPosMs),
        onOpenDetail: (item: MediaItem) => this.openMovieDetail(item)
      })
    } else {
      SettingsView({
        onOpenDecoderPrefs: () => this.pushRoute('pages/DecoderPrefsPage'),
        onOpenCachePrefs: () => this.pushRoute('pages/CachePrefsPage'),
        onOpenSubtitlePrefs: () => this.pushRoute('pages/SubtitlePrefsPage'),
        onOpenShortcuts: () => this.pushRoute('pages/ShortcutsPage'),
        onOpenTmdbConfig: () => this.pushRoute('pages/TmdbConfigPage'),
        onOpenPrivacyVault: () => this.pushRoute('pages/PrivacyVaultPage'),
        onOpenAboutPrivacy: () => this.pushRoute('pages/AboutPrivacyPage'),
        onOpenPrivacyPolicy: () => this.openLegalDoc('privacy'),
        onOpenUserAgreement: () => this.openLegalDoc('agreement')
      })
    }
  }

  build() {
    Stack() {
      if (this.isDesktopOrTablet()) {
        // Tablet & HarmonyOS PC (2in1) Sidebar + Content Shell
        Row() {
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_brand_prism'))
                .width(34)
                .height(34)

              if (!this.sidebarCollapsed) {
                Column({ space: 1 }) {
                  Text('棱镜影院')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                  Text('PrismPlayer')
                    .fontSize(10)
                    .fontColor($r('app.color.text_muted'))
                }.alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 8, bottom: 12 })
            .justifyContent(this.sidebarCollapsed ? FlexAlign.Center : FlexAlign.Start)
            .onClick(() => {
              this.sidebarCollapsed = !this.sidebarCollapsed;
            })

            this.navItem(0, '媒体影库')
            this.navItem(1, '片源管理')
            this.navItem(2, '最近观看')
            this.navItem(3, '设置与 Pro')

            Blank()

            if (!this.sidebarCollapsed) {
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  Image($r('app.media.ic_pro_crown')).width(16).height(16)
                  Text(this.store.isPro ? 'Pro 买断已激活' : '升级 Pro 买断版')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.accent_gold'))
                }
                Text(this.store.isPro ? '手机+平板+PC 通用' : '¥38 起 · 无限源/4K/ASS')
                  .fontSize(11)
                  .fontColor($r('app.color.text_muted'))
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor('#1AF5B841')
              .border({ width: 0.8, color: '#33F5B841' })
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.pushRoute('pages/ProStorePage'))
            }
          }
          .width(this.sidebarCollapsed ? 72 : 220)
          .height('100%')
          .padding(12)
          .backgroundColor($r('app.color.bg_secondary'))
          .border({ width: { right: 0.8 }, color: $r('app.color.border_subtle') })
          .animation({ duration: 180, curve: Curve.EaseOut })

          Column() {
            this.activeContentView()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else {
        // Phone Frosted-Glass Bottom Tab Shell
        Column() {
          Column() {
            this.activeContentView()
          }
          .layoutWeight(1)
          .width('100%')

          Row() {
            this.bottomTabBtn(0, '影库')
            this.bottomTabBtn(1, '片源')
            this.bottomTabBtn(2, '历史')
            this.bottomTabBtn(3, '设置')
          }
          .width('100%')
          .height(60)
          .backgroundColor($r('app.color.bar_glass'))
          .backdropBlur(20)
          .border({ width: { top: 0.8 }, color: $r('app.color.border_subtle') })
        }
        .width('100%')
        .height('100%')
      }

      if (this.store.initialized && !this.store.privacyAccepted) {
        PrivacyConsentDialog({
          onAccept: () => {
            this.store.acceptPrivacyPolicy();
          },
          onDecline: () => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            ctx.terminateSelf();
          },
          onOpenDoc: (docType: string) => this.openLegalDoc(docType)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

import { common } from '@kit.AbilityKit';
import {
  LegalDocParams,
  MediaDetailParams,
  MediaItem,
  MediaSource,
  MusicAlbum,
  MusicLaunchParams,
  PlayerLaunchParams,
  RouteRequest,
  SeriesGroup,
  SourceBrowserParams,
  SourceFormParams
} from '../common/Types';
import { PrivacyConsentDialog } from '../components/PrivacyConsentDialog';
import { Layout } from '../common/Layout';
import { AppConstants } from '../common/Constants';
import { AppStore } from '../services/AppStore';
import { MusicPlayerService } from '../services/MusicPlayerService';
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
  @Local hoverNav: number = -1;

  aboutToAppear(): void {
    // 音乐服务要拿到 AbilityContext 才能申请后台音频长时任务
    MusicPlayerService.getInstance().setContext(
      this.getUIContext().getHostContext() as common.UIAbilityContext
    );
    // 卡片 / 桌面快捷方式 / 状态栏 / 分享链接 / 应用接续 都通过这两个回调落到页面上
    this.store.registerLaunchHandler((params: PlayerLaunchParams) => {
      setTimeout(() => {
        this.pushRoute('pages/PlayerPage', params);
      }, 30);
    });
    this.store.registerTabHandler((index: number) => {
      this.activeTab = index;
    });
    // 分享扩展等外部来源直接指定页面
    this.store.registerRouteHandler((req: RouteRequest) => {
      setTimeout(() => {
        this.pushRoute(req.url, req.params);
      }, 30);
    });
  }

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

  /** 协议正文随包内置（rawfile/legal），不跳浏览器。 */
  private openLegalDoc(docType: string): void {
    this.pushRoute('pages/LegalDocPage', { docType } as LegalDocParams);
  }

  /** 电影列表播放：从第一部开始，播完由播放页自动接下一部。 */
  private playMovieList(items: MediaItem[]): void {
    if (items.length === 0) return;
    const first = items[0];
    const src = this.store.sources.find(s => s.id === first.sourceId);
    const params: PlayerLaunchParams = {
      item: first,
      source: src,
      startPositionMs: this.store.getHistoryForItem(first.id)?.positionMs || 0,
      playlist: items
    };
    this.pushRoute('pages/PlayerPage', params);
  }

  private launchPlayer(item: MediaItem, startPosMs: number): void {
    // 音频条目统一走音乐播放器，视频引擎不处理纯音频
    if (item.mediaType === 'track') {
      this.openMusicTrack(item);
      return;
    }
    const src = this.store.sources.find(s => s.id === item.sourceId);
    const params: PlayerLaunchParams = {
      item,
      source: src,
      startPositionMs: startPosMs
    };
    this.pushRoute('pages/PlayerPage', params);
  }

  private openMusicTrack(item: MediaItem, queue?: MediaItem[]): void {
    const list = queue && queue.length > 0 ? queue : this.store.getMusicQueue(item);
    const params: MusicLaunchParams = { item, queue: list };
    this.pushRoute('pages/MusicPlayerPage', params);
  }

  private playAlbum(album: MusicAlbum): void {
    if (album.tracks.length === 0) return;
    this.openMusicTrack(album.tracks[0], album.tracks);
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
    return Layout.useSidebar(this.store.currentBreakpoint);
  }

  /** md 平板竖屏 / 手机横屏收成图标轨，把宽度让给内容。 */
  private railMode(): boolean {
    return Layout.isRail(this.store.currentBreakpoint) || this.sidebarCollapsed;
  }

  private sidebarWidth(): number {
    return Layout.sidebarWidth(this.store.currentBreakpoint, this.sidebarCollapsed);
  }

  private contentWidth(): number {
    return Layout.contentWidth(this.store.windowWidthVp, this.store.currentBreakpoint, this.sidebarWidth());
  }

  private toggleSidebar(): void {
    if (Layout.isWide(this.store.currentBreakpoint)) {
      this.sidebarCollapsed = !this.sidebarCollapsed;
    }
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
        .fontColor([this.activeTab === index ? $r('app.color.nav_active_fg') : $r('app.color.text_secondary')])
      if (!this.railMode()) {
        Text(label)
          .fontSize(14)
          .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.activeTab === index ? $r('app.color.nav_active_fg') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: this.railMode() ? 0 : 14, right: this.railMode() ? 0 : 14 })
    .borderRadius(12)
    .justifyContent(this.railMode() ? FlexAlign.Center : FlexAlign.Start)
    .backgroundColor(this.activeTab === index
      ? $r('app.color.nav_active_bg')
      : (this.hoverNav === index ? $r('app.color.fill_subtle') : Color.Transparent))
    .border({
      width: this.activeTab === index || this.hoverNav === index ? 0.8 : 0,
      color: this.activeTab === index ? $r('app.color.nav_active_border') : $r('app.color.border_subtle')
    })
    .focusable(true)
    .onHover((isHover: boolean) => {
      this.hoverNav = isHover ? index : -1;
    })
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
        .fontColor(this.activeTab === index ? $r('app.color.accent_blue') : $r('app.color.text_body_muted'))
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
        contentWidth: this.contentWidth(),
        onOpenMovie: (item: MediaItem) => this.openMovieDetail(item),
        onOpenSeries: (grp: SeriesGroup) => this.openSeriesDetail(grp),
        onPlayDirect: (item: MediaItem, startPosMs: number) => this.launchPlayer(item, startPosMs),
        onGoSources: () => { this.activeTab = 1; },
        onOpenSearch: () => this.pushRoute('pages/SearchPage'),
        onOpenVault: () => this.pushRoute('pages/PrivacyVaultPage'),
        onPlayAlbum: (album: MusicAlbum) => this.playAlbum(album),
        onPlayMovieList: (items: MediaItem[]) => this.playMovieList(items),
        onOpenMusicPlayer: () => this.pushRoute('pages/MusicPlayerPage'),
        onOpenLocal: () => this.pushRoute('pages/LocalVideosPage')
      })
    } else if (this.activeTab === 1) {
      SourcesView({
        breakpoint: this.store.currentBreakpoint,
        contentWidth: this.contentWidth(),
        onOpenEditor: (editing: MediaSource | null) => this.openSourceForm(editing),
        onBrowseSource: (src: MediaSource) => this.openSourceBrowser(src),
        onRequestPro: () => this.pushRoute('pages/ProStorePage'),
        onPlayItem: (item: MediaItem, startPosMs: number) => this.launchPlayer(item, startPosMs)
      })
    } else if (this.activeTab === 2) {
      HistoryView({
        breakpoint: this.store.currentBreakpoint,
        onPlayItem: (item: MediaItem, startPosMs: number) => this.launchPlayer(item, startPosMs),
        onOpenDetail: (item: MediaItem) => this.openMovieDetail(item)
      })
    } else {
      SettingsView({
        breakpoint: this.store.currentBreakpoint,
        onOpenDecoderPrefs: () => this.pushRoute('pages/DecoderPrefsPage'),
        onOpenCachePrefs: () => this.pushRoute('pages/CachePrefsPage'),
        onOpenSubtitlePrefs: () => this.pushRoute('pages/SubtitlePrefsPage'),
        onOpenShortcuts: () => this.pushRoute('pages/ShortcutsPage'),
        onOpenTmdbConfig: () => this.pushRoute('pages/TmdbConfigPage'),
        onOpenPrivacyVault: () => this.pushRoute('pages/PrivacyVaultPage'),
        onOpenAboutPrivacy: () => this.pushRoute('pages/AboutPrivacyPage'),
        onOpenPrivacyPolicy: () => this.openLegalDoc('privacy'),
        onOpenUserAgreement: () => this.openLegalDoc('agreement'),
        onRequestPro: () => this.pushRoute('pages/ProStorePage')
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
                .width(this.railMode() ? 32 : 34)
                .height(this.railMode() ? 32 : 34)

              if (!this.railMode()) {
                Column({ space: 1 }) {
                  Text('棱镜播放器')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                  Text('PrismPlayer')
                    .fontSize(10)
                    .fontColor($r('app.color.text_body_muted'))
                }.alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .padding({ left: this.railMode() ? 0 : 8, right: this.railMode() ? 0 : 8, top: 8, bottom: 12 })
            .justifyContent(this.railMode() ? FlexAlign.Center : FlexAlign.Start)
            .onClick(() => this.toggleSidebar())

            this.navItem(0, '棱镜播放器')
            this.navItem(1, '片源管理')
            this.navItem(2, '最近观看')
            this.navItem(3, '设置与 Pro')

            Blank()

            if (!this.railMode()) {
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  Image($r('app.media.ic_pro_crown')).width(16).height(16)
                  Text(this.store.isPro ? 'Pro 买断已激活' : '升级 Pro 买断版')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.accent_gold'))
                    .maxLines(1)
                }
                Text(this.store.isPro ? '手机+平板+PC 通用' : '无限源 / 4K / ASS 字幕')
                  .fontSize(11)
                  .fontColor($r('app.color.text_body_muted'))
                  .maxLines(1)
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
          .width(this.sidebarWidth())
          .height('100%')
          .padding(this.railMode() ? 10 : 12)
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

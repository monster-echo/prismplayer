import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import prismNative from 'libprismplayer.so';
import { AppConstants, BreakpointType } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { ThemeManager } from '../common/ThemeManager';
import {
  AppSettings,
  HiddenFolderRule,
  MediaItem,
  MediaSource,
  PlayerLaunchParams,
  ProTier,
  RemoteFileEntry,
  RouteRequest,
  SeriesGroup,
  SubtitleStyleValues,
  SubtitleTrackOption,
  ThemeMode,
  VaultEntry,
  VaultEntryKind,
  WatchHistoryRecord
} from '../common/Types';
import { CardData, CardSnapshot, CARD_SNAPSHOT_KEY } from './CardSnapshot';
import { CardFormData } from './CardFormData';
import { CardPoster } from './CardPoster';
import { LocalArtwork } from './LocalArtwork';
import { LocalAccess } from './LocalAccess';
import { LocalStorageUsage } from './LocalStorageUsage';
import { ContinuePayload } from './PlaybackHandoff';
import { CryptoVault } from './CryptoVault';
import { DouyinClient, LocalVideoSaveResult } from './DouyinClient';
import { EmbyClient } from './EmbyClient';
import { IptvClient } from './IptvClient';
import { MediaDatabase } from './MediaDatabase';
import { NfoMetadata, NfoParser } from './NfoParser';
import { PlexClient } from './PlexClient';
import { RemoteSourceClient } from './RemoteSourceClient';
import { TmdbCandidate, TmdbScraper } from './TmdbScraper';
import { WebDavClient } from './WebDavClient';
import { YouTubeClient } from './YouTubeClient';

@ObservedV2
export class AppStore {
  private static instance: AppStore | null = null;

  static getInstance(): AppStore {
    if (!AppStore.instance) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  private db: MediaDatabase = new MediaDatabase();
  private context: common.UIAbilityContext | null = null;
  private proxyStarted: boolean = false;

  @Trace initialized: boolean = false;
  @Trace privacyAccepted: boolean = false;
  @Trace settings: AppSettings = {
    themeMode: 'system',
    subdlApiKey: '',
    cacheBudgetMb: AppConstants.DEFAULT_CACHE_MB,
    preferHardwareDecode: true,
    hardwareSupportedFormats: AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS,
    tmdbApiKey: '',
    tmdbApiHost: AppConstants.DEFAULT_TMDB_HOST,
    tmdbImageBase: AppConstants.DEFAULT_TMDB_IMAGE_BASE,
    autoSkipIntroSec: 0,
    autoSkipOutroSec: 0,
    subtitleFontSizeFp: 20,
    subtitleLanguageMode: 'all',
    subtitleBgEnabled: true,
    subtitleBgOpacityPercent: 35,
    subtitleVerticalOffsetVp: 0,
    burnSubMaskDefault: false,
    proTier: 'free',
    privacyAccepted: false,
    vaultPinCipher: ''
  };
  @Trace sources: MediaSource[] = [];
  @Trace mediaItems: MediaItem[] = [];
  @Trace watchHistory: WatchHistoryRecord[] = [];
  @Trace hiddenFolders: HiddenFolderRule[] = [];
  @Trace vaultEntries: VaultEntry[] = [];
  @Trace vaultUnlocked: boolean = false;
  @Trace isScanning: boolean = false;
  @Trace scanStatusText: string = '';
  @Trace proxyPort: number = 0;
  @Trace pendingLaunchItem: MediaItem | null = null;
  /** 卡片 / 快捷方式 / 分享链接 / 系统菜单唤起播放时，等待 UI 侧接手的请求。 */
  @Trace pendingPlayerLaunch: PlayerLaunchParams | null = null;
  @Trace pendingTab: number = -1;
  @Trace pendingRoute: RouteRequest | null = null;
  private launchHandler: ((params: PlayerLaunchParams) => void) | null = null;
  private tabHandler: ((index: number) => void) | null = null;
  private routeHandler: ((req: RouteRequest) => void) | null = null;
  /** 当前播放现场，供 UIAbility.onContinue 读取后跨端迁移。 */
  private livePlayback: ContinuePayload | null = null;
  @Trace currentBreakpoint: BreakpointType = 'sm';
  @Trace isLandscape: boolean = false;
  /** 窗口逻辑尺寸（vp）。页面据此决定内容宽度上限与分栏，而不是各写一套百分比。 */
  @Trace windowWidthVp: number = 360;
  @Trace windowHeightVp: number = 780;

  get isPro(): boolean {
    return this.settings.proTier !== 'free';
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    await this.db.init(context);
    this.settings = await this.db.loadSettings();
    this.privacyAccepted = this.settings.privacyAccepted;
    if (this.privacyAccepted) {
      await this.bootstrapAfterConsent();
    }
    this.initialized = true;
  }

  async acceptPrivacyPolicy(): Promise<void> {
    this.privacyAccepted = true;
    this.settings = {
      themeMode: this.settings.themeMode,
      subdlApiKey: this.settings.subdlApiKey,
      cacheBudgetMb: this.settings.cacheBudgetMb,
      preferHardwareDecode: this.settings.preferHardwareDecode,
      hardwareSupportedFormats: this.settings.hardwareSupportedFormats || AppConstants.DEFAULT_HARDWARE_SUPPORTED_FORMATS,
      tmdbApiKey: this.settings.tmdbApiKey,
      tmdbApiHost: this.settings.tmdbApiHost,
      tmdbImageBase: this.settings.tmdbImageBase,
      autoSkipIntroSec: this.settings.autoSkipIntroSec,
      autoSkipOutroSec: this.settings.autoSkipOutroSec,
      subtitleFontSizeFp: this.settings.subtitleFontSizeFp,
      subtitleLanguageMode: this.settings.subtitleLanguageMode,
      subtitleBgEnabled: this.settings.subtitleBgEnabled,
      subtitleBgOpacityPercent: this.settings.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: this.settings.subtitleVerticalOffsetVp,
      burnSubMaskDefault: this.settings.burnSubMaskDefault,
      proTier: this.settings.proTier,
      privacyAccepted: true,
      vaultPinCipher: this.settings.vaultPinCipher || ''
    };
    await this.db.saveSettings(this.settings);
    await this.bootstrapAfterConsent();
  }

  private async bootstrapAfterConsent(): Promise<void> {
    this.ensureNativeProxy();
    await this.reloadAllData();
    // 本机视频的持久授权必须每次启动重新激活，否则条目全部打不开
    this.activateLocalPermissions().catch(() => {});
    await this.purgeLegacyDemoLibrary();
  }

  /**
   * 旧版本首次启动会写入 3 部演示片（source_id = demo_showcase）。应用市场要求正式版本
   * 不得内置测试数据，这里在升级安装时清掉遗留条目与其观看历史；没有残留直接返回。
   */
  private async purgeLegacyDemoLibrary(): Promise<void> {
    const hasDemo = this.mediaItems.some((m: MediaItem) => m.sourceId === 'demo_showcase');
    if (!hasDemo) return;
    await this.db.deleteSource('demo_showcase');
    this.mediaItems = await this.db.listMediaItems();
    this.watchHistory = await this.db.listWatchHistory();
    await this.refreshCardSnapshot();
  }

  ensureNativeProxy(): number {
    if (this.proxyStarted && this.proxyPort > 0) {
      return this.proxyPort;
    }
    try {
      prismNative.setHttpsFetchHandler(
        (reqId: number, url: string, authHeader: string, rangeStart: number, rangeEnd: number, allowInsecure: boolean) => {
          WebDavClient.fetchRangeChunkForNative(url, authHeader, rangeStart, rangeEnd, allowInsecure)
            .then((res) => {
              prismNative.resolveHttpsChunk(
                reqId,
                res.statusCode,
                res.totalSize,
                res.contentType,
                res.redirectUrl,
                res.data
              );
            })
            .catch(() => {
              prismNative.resolveHttpsChunk(reqId, 0, -1, 'application/octet-stream', '', new ArrayBuffer(0));
            });
        }
      );
      this.proxyPort = prismNative.startStreamProxy(this.settings.cacheBudgetMb);
      this.proxyStarted = this.proxyPort > 0;
    } catch (_e) {
      this.proxyPort = 0;
    }
    return this.proxyPort;
  }

  async reloadAllData(): Promise<void> {
    this.sources = await this.db.listSources();
    this.mediaItems = await this.db.listMediaItems();
    this.watchHistory = await this.db.listWatchHistory();
    this.hiddenFolders = await this.db.listHiddenFolders();
    this.vaultEntries = await this.db.listVaultEntries();
    await this.migrateFolderRulesToVault();
    await this.refreshCardSnapshot();
  }

  // ---------------------------------------------------------------- 播放唤起

  /**
   * UI 层注册「请开始播放」的接手方。冷启动时 AppStore 可能先于页面就绪，
   * 这里保留待办并在注册瞬间立刻补发，避免卡片/快捷方式点进来没有反应。
   */
  registerLaunchHandler(handler: (params: PlayerLaunchParams) => void): void {
    this.launchHandler = handler;
    const pending = this.pendingPlayerLaunch;
    if (pending) {
      this.pendingPlayerLaunch = null;
      handler(pending);
    }
  }

  /** 通用页面跳转：分享扩展之类的外部来源只需要说「去哪个页面、带什么参数」。 */
  registerRouteHandler(handler: (req: RouteRequest) => void): void {
    this.routeHandler = handler;
    const pending = this.pendingRoute;
    if (pending) {
      this.pendingRoute = null;
      handler(pending);
    }
  }

  requestRoute(url: string, params: Object): void {
    const req: RouteRequest = { url, params };
    if (this.routeHandler) {
      this.routeHandler(req);
    } else {
      this.pendingRoute = req;
    }
  }

  registerTabHandler(handler: (index: number) => void): void {
    this.tabHandler = handler;
    const pending = this.pendingTab;
    if (pending >= 0) {
      this.pendingTab = -1;
      handler(pending);
    }
  }

  requestTab(index: number): void {
    if (this.tabHandler) {
      this.tabHandler(index);
    } else {
      this.pendingTab = index;
    }
  }

  setLivePlayback(payload: ContinuePayload | null): void {
    this.livePlayback = payload;
  }

  getLivePlayback(): ContinuePayload | null {
    return this.livePlayback;
  }

  private requestPlayerLaunch(params: PlayerLaunchParams): void {
    if (this.launchHandler) {
      this.launchHandler(params);
    } else {
      this.pendingPlayerLaunch = params;
    }
  }

  findMediaItemById(itemId: string): MediaItem | undefined {
    return this.mediaItems.find(m => m.id === itemId);
  }

  private launchParamsFor(item: MediaItem, positionMs: number, rate: number): PlayerLaunchParams {
    const source = this.sources.find(s => s.id === item.sourceId);
    return { item, source, startPositionMs: positionMs, playbackRate: rate };
  }

  /** 指定条目 + 进度起播（卡片、快捷方式、App Linking 共用）。 */
  async requestResumePlayback(itemId: string, positionMs: number): Promise<boolean> {
    const item = this.findMediaItemById(itemId);
    if (!item) return false;
    const hist = this.getHistoryForItem(itemId);
    const rate = hist && hist.playbackRate > 0 ? hist.playbackRate : 1.0;
    const startMs = positionMs > 0 ? positionMs : (hist ? hist.positionMs : 0);
    this.requestPlayerLaunch(this.launchParamsFor(item, startMs, rate));
    return true;
  }

  /** 「继续观看」：取卡片的同一条策略，隐私条目永不命中。 */
  async requestContinueWatching(): Promise<boolean> {
    const concealed = this.concealedIds();
    for (let i = 0; i < this.watchHistory.length; i++) {
      const rec = this.watchHistory[i];
      if (rec.finished || rec.durationMs <= 0) continue;
      if (concealed.has(rec.itemId)) continue;
      return await this.requestResumePlayback(rec.itemId, rec.positionMs);
    }
    return false;
  }

  /** 服务卡片走的隐私判定集合：不看 vaultUnlocked，桌面属于公共区域。 */
  private concealedIds(): Set<string> {
    const ids = new Set<string>();
    for (let i = 0; i < this.mediaItems.length; i++) {
      const it = this.mediaItems[i];
      if (this.isPathRuleHidden(it.sourceId, it.remotePath) || this.isContentVaultHidden(it)) {
        ids.add(it.id);
      }
    }
    return ids;
  }

  /** 把「继续观看」算好写进 preferences，卡片进程只读这一份。 */
  async refreshCardSnapshot(): Promise<void> {
    const data: CardData = CardSnapshot.build(this.watchHistory, this.concealedIds());
    // 先落文字版本：这条路径在启动/每次进度保存时都会跑，不能被网络图拖住
    await this.db.setStringPref(CARD_SNAPSHOT_KEY, CardSnapshot.toJson(data));
    if (!data.hasData) return;
    this.hydrateCardPoster(data).catch(() => {});
  }

  /** 海报是加分项：download 失败或超时就保持纯文字卡片。 */
  private async hydrateCardPoster(data: CardData): Promise<void> {
    if (!this.context) return;
    if (CardPoster.isUsable(data.posterUrl)) {
      const path: string = await CardPoster.ensure(this.context, data.posterUrl);
      if (path) {
        data.posterPath = path;
        data.hasPoster = true;
        await this.db.setStringPref(CARD_SNAPSHOT_KEY, CardSnapshot.toJson(data));
      }
    }
    // 桌面已添加卡片时立刻推送，不必等用户重新添加或系统定时刷新
    await CardFormData.push(this.context, data);
  }

  async getNumberPref(key: string, def: number): Promise<number> {
    return await this.db.getNumberPref(key, def);
  }

  async setNumberPref(key: string, value: number): Promise<void> {
    await this.db.setNumberPref(key, value);
  }

  hasVaultPattern(): boolean {
    return !!this.settings.vaultPinCipher;
  }

  async setVaultPattern(newPattern: string): Promise<void> {
    const clean = newPattern.trim();
    const cipher = clean ? await CryptoVault.encrypt(clean) : '';
    await this.updateSettings({
      themeMode: this.settings.themeMode,
      subdlApiKey: this.settings.subdlApiKey,
      cacheBudgetMb: this.settings.cacheBudgetMb,
      preferHardwareDecode: this.settings.preferHardwareDecode,
      hardwareSupportedFormats: this.settings.hardwareSupportedFormats,
      tmdbApiKey: this.settings.tmdbApiKey,
      tmdbApiHost: this.settings.tmdbApiHost,
      tmdbImageBase: this.settings.tmdbImageBase,
      autoSkipIntroSec: this.settings.autoSkipIntroSec,
      autoSkipOutroSec: this.settings.autoSkipOutroSec,
      subtitleFontSizeFp: this.settings.subtitleFontSizeFp,
      subtitleLanguageMode: this.settings.subtitleLanguageMode,
      subtitleBgEnabled: this.settings.subtitleBgEnabled,
      subtitleBgOpacityPercent: this.settings.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: this.settings.subtitleVerticalOffsetVp,
      burnSubMaskDefault: this.settings.burnSubMaskDefault,
      proTier: this.settings.proTier,
      privacyAccepted: this.settings.privacyAccepted,
      vaultPinCipher: cipher
    });
  }

  async verifyVaultPattern(candidate: string): Promise<boolean> {
    if (!this.settings.vaultPinCipher) return false;
    const stored = await CryptoVault.decrypt(this.settings.vaultPinCipher);
    return stored.length > 0 && stored === candidate.trim();
  }

  async unlockVault(pattern: string): Promise<boolean> {
    const ok = await this.verifyVaultPattern(pattern);
    if (ok) {
      this.vaultUnlocked = true;
    }
    return ok;
  }

  lockVault(): void {
    this.vaultUnlocked = false;
  }

  private normalizeRelPath(path: string): string {
    let p = (path || '/').replace(/\\/g, '/').trim();
    if (!p.startsWith('/')) p = '/' + p;
    return p.replace(/\/+$/, '') || '/';
  }

  isPathRuleHidden(sourceId: string, remotePath: string): boolean {
    const normTarget = this.normalizeRelPath(remotePath);
    for (let i = 0; i < this.hiddenFolders.length; i++) {
      const rule = this.hiddenFolders[i];
      if (rule.sourceId !== sourceId) continue;
      const normRule = this.normalizeRelPath(rule.folderPath);
      if (normTarget === normRule || normTarget.startsWith(normRule + '/')) {
        return true;
      }
    }
    return false;
  }

  shouldConcealPath(sourceId: string, remotePath: string): boolean {
    if (this.vaultUnlocked) return false;
    return this.isPathRuleHidden(sourceId, remotePath);
  }

  getVisibleMediaItems(): MediaItem[] {
    if (this.vaultUnlocked) {
      return this.mediaItems;
    }
    if (this.hiddenFolders.length === 0 && this.vaultEntries.length === 0) {
      return this.mediaItems;
    }
    return this.mediaItems.filter(it =>
      !this.shouldConcealPath(it.sourceId, it.remotePath) && !this.isContentVaultHidden(it)
    );
  }

  getHiddenMediaItems(): MediaItem[] {
    if (!this.vaultUnlocked) {
      return [];
    }
    return this.mediaItems.filter(it => this.isPathRuleHidden(it.sourceId, it.remotePath) || this.isContentVaultHidden(it));
  }

  /** 内容级保险库隐藏判断：剧集按 seriesKey 全集隐藏，电影按条目 ID 精确隐藏。 */
  isContentVaultHidden(item: MediaItem): boolean {
    for (let i = 0; i < this.vaultEntries.length; i++) {
      const entry = this.vaultEntries[i];
      if (entry.kind === 'folder') continue;
      if (entry.kind === 'series' && item.mediaType === 'episode' && entry.targetKey === item.seriesKey) {
        return true;
      }
      if (entry.kind === 'movie' && entry.targetKey === item.id) {
        return true;
      }
    }
    return false;
  }

  /** 隐藏一部剧集（按 seriesKey，跨季跨目录）或一部电影（按条目 ID）。 */
  async hideToVault(item: MediaItem): Promise<void> {
    const isSeries = item.mediaType === 'episode';
    const targetKey = isSeries ? item.seriesKey : item.id;
    if (!targetKey) return;
    const id = `${item.sourceId}::${isSeries ? 'series' : 'movie'}::${targetKey}`;
    if (this.vaultEntries.some(v => v.id === id)) return;
    await this.db.upsertVaultEntry({
      id,
      sourceId: item.sourceId,
      kind: isSeries ? 'series' : 'movie',
      targetKey,
      title: isSeries ? (item.seriesTitle || item.title) : item.title,
      posterUrl: item.posterUrl || '',
      createdAt: Date.now()
    });
    this.vaultEntries = await this.db.listVaultEntries();
    await this.reloadAllData();
  }

  /** 目录级快捷隐藏：写路径规则（沿用旧过滤），同时登记一条 folder 保险库条目。 */
  async hideFolderToVault(sourceId: string, folderPath: string, folderName: string): Promise<void> {
    const norm = this.normalizeRelPath(folderPath);
    await this.hideFolder(sourceId, folderPath, folderName);
    const id = `${sourceId}::folder::${norm}`;
    if (this.vaultEntries.some(v => v.id === id)) return;
    await this.db.upsertVaultEntry({
      id,
      sourceId,
      kind: 'folder',
      targetKey: norm,
      title: folderName || norm,
      posterUrl: '',
      createdAt: Date.now()
    });
    this.vaultEntries = await this.db.listVaultEntries();
    await this.reloadAllData();
  }

  /** 取消一条保险库条目；folder 类型同时删除底层路径规则。 */
  async unhideVaultEntry(entry: VaultEntry): Promise<void> {
    if (entry.kind === 'folder') {
      const ruleId = `${entry.sourceId}::${entry.targetKey}`;
      await this.db.deleteHiddenFolder(ruleId);
      this.hiddenFolders = await this.db.listHiddenFolders();
    }
    await this.db.deleteVaultEntry(entry.id);
    this.vaultEntries = await this.db.listVaultEntries();
    await this.refreshCardSnapshot();
  }

  /** 旧文件夹规则一次性迁移为 folder 保险库条目（幂等）。 */
  private async migrateFolderRulesToVault(): Promise<void> {
    let changed = false;
    for (let i = 0; i < this.hiddenFolders.length; i++) {
      const rule = this.hiddenFolders[i];
      const id = `folder::${rule.id}`;
      if (this.vaultEntries.some(v => v.id === id)) continue;
      await this.db.upsertVaultEntry({
        id,
        sourceId: rule.sourceId,
        kind: 'folder',
        targetKey: rule.folderPath,
        title: rule.folderName,
        posterUrl: '',
        createdAt: rule.createdAt
      });
      changed = true;
    }
    if (changed) {
      this.vaultEntries = await this.db.listVaultEntries();
    }
  }

  getFavoriteMediaItems(): MediaItem[] {
    return this.getVisibleMediaItems().filter(it => it.isFavorite === true);
  }

  async toggleFavorite(itemId: string): Promise<boolean> {
    const idx = this.mediaItems.findIndex(it => it.id === itemId);
    if (idx < 0) return false;
    const item = this.mediaItems[idx];
    const nextFav = !item.isFavorite;
    item.isFavorite = nextFav;
    await this.db.upsertMediaItems([item]);
    this.mediaItems = await this.db.listMediaItems();
    return nextFav;
  }

  getVisibleWatchHistory(): WatchHistoryRecord[] {
    if (this.vaultUnlocked || (this.hiddenFolders.length === 0 && this.vaultEntries.length === 0)) {
      return this.watchHistory;
    }
    const visibleIds = new Set<string>(this.getVisibleMediaItems().map(m => m.id));
    return this.watchHistory.filter(h => visibleIds.has(h.itemId) || !this.mediaItems.some(m => m.id === h.itemId));
  }

  async hideFolder(sourceId: string, folderPath: string, folderName: string): Promise<void> {
    const norm = this.normalizeRelPath(folderPath);
    const id = `${sourceId}::${norm}`;
    await this.db.upsertHiddenFolder({
      id,
      sourceId,
      folderPath: norm,
      folderName: folderName || norm,
      createdAt: Date.now()
    });
    this.hiddenFolders = await this.db.listHiddenFolders();
  }

  async unhideFolder(ruleId: string): Promise<void> {
    await this.db.deleteHiddenFolder(ruleId);
    this.hiddenFolders = await this.db.listHiddenFolders();
    await this.db.deleteVaultEntry(`folder::${ruleId}`);
    this.vaultEntries = await this.db.listVaultEntries();
    await this.reloadAllData();
  }

  async updateSettings(next: AppSettings): Promise<void> {
    this.settings = next;
    await this.db.saveSettings(next);
  }

  /** 写入买断等级（IAP 支付成功或恢复购买后调用）。 */
  async applyProTier(tier: ProTier): Promise<void> {
    if (this.settings.proTier === tier) return;
    const s = this.settings;
    await this.updateSettings({
      themeMode: s.themeMode,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      autoSkipOutroSec: s.autoSkipOutroSec,
      subtitleFontSizeFp: s.subtitleFontSizeFp,
      subtitleLanguageMode: s.subtitleLanguageMode,
      subtitleBgEnabled: s.subtitleBgEnabled,
      subtitleBgOpacityPercent: s.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: s.subtitleVerticalOffsetVp,
      burnSubMaskDefault: s.burnSubMaskDefault,
      subdlApiKey: s.subdlApiKey,
      proTier: tier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher || ''
    });
  }

  /** 跳过片头/片尾的秒数（0 = 关闭），全局默认，作用于剧集。 */
  async saveSkipDefaults(introSec: number, outroSec: number): Promise<void> {
    const s = this.settings;
    await this.updateSettings({
      themeMode: s.themeMode,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: introSec,
      autoSkipOutroSec: outroSec,
      subtitleFontSizeFp: s.subtitleFontSizeFp,
      subtitleLanguageMode: s.subtitleLanguageMode,
      subtitleBgEnabled: s.subtitleBgEnabled,
      subtitleBgOpacityPercent: s.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: s.subtitleVerticalOffsetVp,
      burnSubMaskDefault: s.burnSubMaskDefault,
      subdlApiKey: s.subdlApiKey,
      proTier: s.proTier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher
    });
  }

  /**
   * Centralized write path for subtitle appearance defaults.
   * Keeps the player style screen and the settings page on one source of truth.
   */
  async saveSubtitleDefaults(style: SubtitleStyleValues): Promise<void> {
    const s = this.settings;
    await this.updateSettings({
      themeMode: s.themeMode,
      subdlApiKey: s.subdlApiKey,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      autoSkipOutroSec: s.autoSkipOutroSec,
      subtitleFontSizeFp: style.fontSizeFp,
      subtitleLanguageMode: style.languageMode,
      subtitleBgEnabled: style.bgEnabled,
      subtitleBgOpacityPercent: style.bgOpacityPercent,
      subtitleVerticalOffsetVp: style.verticalOffsetVp,
      burnSubMaskDefault: s.burnSubMaskDefault,
      proTier: s.proTier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher || ''
    });
  }

  async saveBurnSubMaskDefault(enabled: boolean): Promise<void> {
    const s = this.settings;
    await this.updateSettings({
      themeMode: s.themeMode,
      subdlApiKey: s.subdlApiKey,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      autoSkipOutroSec: s.autoSkipOutroSec,
      subtitleFontSizeFp: s.subtitleFontSizeFp,
      subtitleLanguageMode: s.subtitleLanguageMode,
      subtitleBgEnabled: s.subtitleBgEnabled,
      subtitleBgOpacityPercent: s.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: s.subtitleVerticalOffsetVp,
      burnSubMaskDefault: enabled,
      proTier: s.proTier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher || ''
    });
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    const s = this.settings;
    await this.updateSettings({
      themeMode: mode,
      subdlApiKey: s.subdlApiKey,
      cacheBudgetMb: s.cacheBudgetMb,
      preferHardwareDecode: s.preferHardwareDecode,
      hardwareSupportedFormats: s.hardwareSupportedFormats,
      tmdbApiKey: s.tmdbApiKey,
      tmdbApiHost: s.tmdbApiHost,
      tmdbImageBase: s.tmdbImageBase,
      autoSkipIntroSec: s.autoSkipIntroSec,
      autoSkipOutroSec: s.autoSkipOutroSec,
      subtitleFontSizeFp: s.subtitleFontSizeFp,
      subtitleLanguageMode: s.subtitleLanguageMode,
      subtitleBgEnabled: s.subtitleBgEnabled,
      subtitleBgOpacityPercent: s.subtitleBgOpacityPercent,
      subtitleVerticalOffsetVp: s.subtitleVerticalOffsetVp,
      burnSubMaskDefault: s.burnSubMaskDefault,
      proTier: s.proTier,
      privacyAccepted: s.privacyAccepted,
      vaultPinCipher: s.vaultPinCipher || ''
    });
    ThemeManager.applyMode(mode);
  }

  canAddSource(): boolean {
    if (this.isPro) return true;
    return this.sources.length < AppConstants.FREE_MAX_SOURCES;
  }

  async saveSource(source: MediaSource): Promise<void> {
    await this.db.upsertSource(source);
    this.sources = await this.db.listSources();
  }

  async deleteSource(sourceId: string): Promise<void> {
    await this.db.deleteSource(sourceId);
    await this.reloadAllData();
  }

  async clearSourceIndex(sourceId: string): Promise<void> {
    await this.db.clearSourceMediaItems(sourceId);
    await this.reloadAllData();
    this.scanStatusText = '已清理该片源本地影库索引';
  }

  sourceItemCount(sourceId: string): number {
    let count = 0;
    for (let i = 0; i < this.mediaItems.length; i++) {
      if (this.mediaItems[i].sourceId === sourceId) count++;
    }
    return count;
  }

  async scanSource(source: MediaSource): Promise<number> {
    if (source.type === 'local') {
      return 0;
    }
    this.isScanning = true;
    this.scanStatusText = `正在连接 ${source.name}...`;
    const discovered: MediaItem[] = [];
    const maxItems = 100000;
    try {
      if (source.type === 'plex') {
        this.scanStatusText = `正在同步 Plex 媒体库...`;
        const plexItems = await PlexClient.scanLibraryItems(source, maxItems);
        for (let i = 0; i < plexItems.length; i++) discovered.push(plexItems[i]);
      } else if (source.type === 'emby') {
        this.scanStatusText = `正在同步 Emby / Jellyfin 媒体库...`;
        const embyItems = await EmbyClient.scanLibraryItems(source, maxItems);
        for (let i = 0; i < embyItems.length; i++) discovered.push(embyItems[i]);
      } else if (source.type === 'youtube') {
        this.scanStatusText = `正在抓取 YouTube 频道与视频封面...`;
        const ytItems = await YouTubeClient.scanLibraryItems(source, maxItems);
        for (let i = 0; i < ytItems.length; i++) discovered.push(ytItems[i]);
      } else if (source.type === 'douyin') {
        this.scanStatusText = `正在解析抖音分享视频与无水印地址...`;
        const dyItems = await DouyinClient.scanLibraryItems(source);
        for (let i = 0; i < dyItems.length; i++) discovered.push(dyItems[i]);
      } else if (source.type === 'iptv') {
        this.scanStatusText = `正在解析 IPTV / 流媒体订阅...`;
        const iptvItems = await IptvClient.scanLibraryItems(source, maxItems);
        if (iptvItems.length > 0) {
          for (let i = 0; i < iptvItems.length; i++) discovered.push(iptvItems[i]);
        } else {
          await this.walkRemoteDir(source, source.rootPath || '/', 0, discovered);
        }
      } else {
        await this.walkRemoteDir(source, source.rootPath || '/', 0, discovered);
      }
      if (discovered.length > 0) {
        await this.db.upsertMediaItems(discovered);
      }
      source.lastScannedAt = Date.now();
      await this.db.upsertSource(source);
      await this.reloadAllData();
      this.scanStatusText = `扫描完成：共入库 ${discovered.length} 部媒体`;
      return discovered.length;
    } catch (e) {
      this.scanStatusText = `扫描异常：${e instanceof Error ? e.message : String(e)}`;
      return 0;
    } finally {
      this.isScanning = false;
    }
  }

  private async walkRemoteDir(
    source: MediaSource,
    dirPath: string,
    depth: number,
    out: MediaItem[]
  ): Promise<void> {
    if (depth > 4 || out.length >= 5000) return;
    this.scanStatusText = `正在扫描 ${dirPath}`;
    let entries: RemoteFileEntry[] = [];
    try {
      entries = await RemoteSourceClient.listDirectory(source, dirPath);
    } catch (_e) {
      return;
    }

    const subtitleEntries: RemoteFileEntry[] = []; // kept: dir-level NFO scan below also iterates entries
    let dirNfoXml = '';
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (e.isSubtitle) {
        subtitleEntries.push(e);
      } else if (!e.isDirectory && e.name.toLowerCase() === 'tvshow.nfo') {
        dirNfoXml = await RemoteSourceClient.fetchText(e.fullUrl, source).catch(() => '');
      }
    }
    const seriesNfo = dirNfoXml ? NfoParser.parse(dirNfoXml) : null;

    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (e.isDirectory) {
        await this.walkRemoteDir(source, e.path, depth + 1, out);
        continue;
      }
      if (!e.isVideo) continue;

      const parsed = Formatters.parseMediaFilename(e.name);
      const matchedSubs = Formatters.matchSidecarSubtitles(entries, e.name);
      const baseLower = Formatters.stripExtension(e.name).toLowerCase();
      const subtitleUrl = matchedSubs.length > 0 ? matchedSubs[0].url : '';

      // Check matching .nfo file
      let fileNfo: NfoMetadata | null = null;
      const nfoEntry = entries.find(x => !x.isDirectory && x.name.toLowerCase() === `${baseLower}.nfo`);
      if (nfoEntry) {
        const xml = await RemoteSourceClient.fetchText(nfoEntry.fullUrl, source).catch(() => '');
        fileNfo = NfoParser.parse(xml);
      }

      const effectiveTitle = (fileNfo && fileNfo.title) ? fileNfo.title : parsed.cleanTitle;
      const seriesTitle = (seriesNfo && seriesNfo.title) ? seriesNfo.title : parsed.cleanTitle;
      const seriesKey = parsed.mediaType === 'episode'
        ? `${source.id}_${seriesTitle.toLowerCase()}`
        : `${source.id}_${e.path}`;

      let item: MediaItem = {
        id: `${source.id}_${e.path}`,
        sourceId: source.id,
        sourceType: source.type,
        remotePath: e.path,
        streamUrl: e.fullUrl,
        fileName: e.name,
        fileSize: e.size,
        mediaType: parsed.mediaType,
        seriesKey,
        seriesTitle,
        seasonNo: fileNfo && fileNfo.seasonNo ? fileNfo.seasonNo : parsed.seasonNo,
        episodeNo: fileNfo && fileNfo.episodeNo ? fileNfo.episodeNo : parsed.episodeNo,
        title: parsed.mediaType === 'episode'
          ? `第 ${parsed.episodeNo} 集 · ${effectiveTitle}`
          : effectiveTitle,
        originalTitle: fileNfo ? fileNfo.originalTitle : '',
        year: (fileNfo && fileNfo.year) ? fileNfo.year : (seriesNfo ? seriesNfo.year : parsed.year),
        overview: (fileNfo && fileNfo.overview) ? fileNfo.overview : (seriesNfo ? seriesNfo.overview : ''),
        posterUrl: (fileNfo && fileNfo.posterUrl) ? fileNfo.posterUrl : (seriesNfo ? seriesNfo.posterUrl : ''),
        backdropUrl: '',
        rating: (fileNfo && fileNfo.rating) ? fileNfo.rating : (seriesNfo ? seriesNfo.rating : 0),
        qualityTag: parsed.qualityTag,
        tmdbId: (fileNfo && fileNfo.tmdbId) ? fileNfo.tmdbId : (seriesNfo ? seriesNfo.tmdbId : 0),
        durationMs: 0,
        subtitleUrl,
        subtitleTracks: matchedSubs,
        addedAt: Date.now()
      };

      // 同目录图片封面（Kodi/Emby 风格）：NAS 影库普遍这么放，优先于 TMDB
      if (!item.posterUrl && this.context) {
        const thumbHint = (fileNfo && fileNfo.thumbRaw) ? fileNfo.thumbRaw
          : ((seriesNfo && seriesNfo.thumbRaw) ? seriesNfo.thumbRaw : '');
        const art = LocalArtwork.pick(entries, e.name, thumbHint);
        if (art) {
          const local = await LocalArtwork.materialize(this.context, source, art);
          if (local) item.posterUrl = local;
        }
      }

      if (this.settings.tmdbApiKey && !item.posterUrl) {
        item = await TmdbScraper.enrichItem(item, this.settings);
      }
      out.push(item);
    }
  }

  async importLocalVideos(): Promise<MediaItem[]> {
    if (!this.context) return [];
    const docPicker = new picker.DocumentViewPicker(this.context);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 50;
    opts.fileSuffixFilters = ['视频|.mp4,.mkv,.mov,.m4v,.webm,.ts,.avi,.flv'];
    const uris = await docPicker.select(opts);
    if (!uris || uris.length === 0) return [];

    const imported: MediaItem[] = [];
    const granted: string[] = [];
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      const decoded = decodeURIComponent(uri);
      const slash = decoded.lastIndexOf('/');
      const fileName = slash >= 0 ? decoded.substring(slash + 1) : `local_${i}.mp4`;
      if (!Formatters.isVideoFile(fileName)) continue;
      const item = await this.buildLocalItem(uri, fileName);
      if (!item) continue;
      imported.push(item);
      granted.push(uri);
    }

    // 先把授权固化，再入库：顺序反了的话，重启后就是一堆打不开的条目
    await LocalAccess.persist(granted);
    await this.commitLocalItems(imported);
    return imported;
  }

  /** 选一个文件夹，把里面（含子目录）的视频全部导入。手机上没有全盘扫描权限，这是唯一可行的批量方式。 */
  async importLocalFolder(): Promise<MediaItem[]> {
    if (!this.context) return [];
    const docPicker = new picker.DocumentViewPicker(this.context);
    const opts = new picker.DocumentSelectOptions();
    opts.selectMode = picker.DocumentSelectMode.FOLDER;
    opts.maxSelectNumber = 1;
    const dirs = await docPicker.select(opts);
    if (!dirs || dirs.length === 0) return [];

    const dir = dirs[0];
    const files: string[] = [];
    await AppStore.collectVideoUris(dir, files, 0);
    if (files.length === 0) return [];

    // 目录本身也要授权，否则子项即便持久化过，父目录不可达时仍会失败
    await LocalAccess.persist([dir].concat(files));

    const imported: MediaItem[] = [];
    for (let i = 0; i < files.length; i++) {
      const uri = files[i];
      const decoded = decodeURIComponent(uri);
      const slash = decoded.lastIndexOf('/');
      const fileName = slash >= 0 ? decoded.substring(slash + 1) : `local_${i}.mp4`;
      const item = await this.buildLocalItem(uri, fileName);
      if (item) imported.push(item);
    }
    await this.commitLocalItems(imported);
    return imported;
  }

  /**
   * 递归收集视频文件。
   * 必须用异步 IO：用户可能选整个「我的手机」，同步遍历会把主线程卡住。
   */
  private static async collectVideoUris(dir: string, out: string[], depth: number): Promise<void> {
    if (depth > 6 || out.length > 2000) return;
    let names: string[] = [];
    try {
      names = await fs.listFile(dir);
    } catch (e) {
      hilog.warn(0x0001, 'PrismLocal', 'list failed depth=%{public}d: %{public}s', depth, JSON.stringify(e));
      return;
    }
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (name.startsWith('.')) continue;
      const child = `${dir}/${name}`;
      let isDir = false;
      try {
        isDir = (await fs.stat(child)).isDirectory();
      } catch (_e) {
        continue;
      }
      if (isDir) {
        await AppStore.collectVideoUris(child, out, depth + 1);
      } else if (Formatters.isVideoFile(name)) {
        out.push(child);
      }
    }
  }

  private async buildLocalItem(uri: string, fileName: string): Promise<MediaItem | null> {
    if (!Formatters.isVideoFile(fileName)) return null;
    let durationMs = 0;
    let fileSize = 0;
    let width = 0;
    let height = 0;
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      fileSize = stat.size;
      const meta = prismNative.probeLocalMedia(file.fd, 0, stat.size);
      durationMs = meta.durationMs;
      width = meta.width;
      height = meta.height;
      fs.closeSync(file.fd);
    } catch (_e) {
      // 探测失败不阻断导入：能打开就算可用，播放时再兜底
    }

    const parsed = Formatters.parseMediaFilename(fileName);
    const qTag = height >= 2160 ? '4K' : (height >= 1080 ? '1080P' : parsed.qualityTag);
    return {
      id: `local_${uri}`,
      sourceId: 'local_device',
      sourceType: 'local',
      remotePath: uri,
      streamUrl: uri,
      fileName,
      fileSize,
      mediaType: parsed.mediaType,
      seriesKey: `local_${parsed.cleanTitle.toLowerCase()}`,
      seriesTitle: parsed.cleanTitle,
      seasonNo: parsed.seasonNo,
      episodeNo: parsed.episodeNo,
      title: parsed.cleanTitle,
      originalTitle: '',
      year: parsed.year,
      overview: width > 0 ? `本地视频文件 · ${width}×${height}` : '本地设备导入视频',
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      qualityTag: qTag,
      tmdbId: 0,
      durationMs,
      subtitleUrl: '',
      addedAt: Date.now()
    };
  }

  private async commitLocalItems(items: MediaItem[]): Promise<void> {
    if (items.length === 0) return;
    await this.db.upsertMediaItems(items);
    await this.reloadAllData();
  }

  /** 启动时重新激活本机视频的持久授权，否则重启后条目全变死链。 */
  async activateLocalPermissions(): Promise<void> {
    const uris: string[] = [];
    for (let i = 0; i < this.mediaItems.length; i++) {
      const item = this.mediaItems[i];
      if (item.sourceType === 'local' && item.remotePath) uris.push(item.remotePath);
    }
    await LocalAccess.activate(uris);
  }

  /**
   * Resolves a Douyin share link or share command, adds it to the library,
   * and optionally downloads the watermark-free MP4 to local device storage.
   */
  async resolveDouyinShareAndImport(shareText: string, saveOfflineNow: boolean = false): Promise<MediaItem> {
    const info = await DouyinClient.resolveShareLink(shareText);
    const item = DouyinClient.toMediaItem(info, 'douyin_share');
    if (saveOfflineNow && this.context) {
      const saved = await DouyinClient.saveVideoToLocal(item.streamUrl, item.title, this.context, {
        fileNameHint: item.fileName
      });
      if (saved.ok && saved.localPath) {
        item.streamUrl = saved.localPath;
        item.fileSize = saved.fileSize;
        item.qualityTag = '抖音已离线保存';
      }
    }
    await this.db.upsertMediaItems([item]);
    await this.reloadAllData();
    return item;
  }

  /**
   * 播放时惰性补关联：旧条目（sidecar 匹配上线前入库）字幕字段为空时，
   * 列出视频同目录、按现有规则匹配 sidecar 字幕，写回数据库并同步内存缓存。
   */
  async probeSubtitlesForItem(item: MediaItem, source?: MediaSource, force: boolean = false): Promise<SubtitleTrackOption[]> {
    if (!force && item.subtitleTracks && item.subtitleTracks.length > 0) {
      return item.subtitleTracks;
    }
    if (!source || !item.remotePath || item.remotePath.startsWith('/douyin/')) {
      return [];
    }
    if (source.type === 'youtube' || source.type === 'douyin' || source.type === 'iptv' || source.type === 'local') {
      return [];
    }
    if (source.type === 'plex') {
      try {
        const tracks = await PlexClient.probeSubtitleTracks(source, item);
        hilog.info(0x0001, 'PrismPlex', 'probe id=%{public}s tracks=%{public}d path=%{public}s', item.id, tracks.length, item.remotePath);
        if (tracks.length === 0) return [];
        await this.db.updateMediaItemSubtitles(item.id, tracks[0].url, tracks);
        const idx = this.mediaItems.findIndex(m => m.id === item.id);
        if (idx >= 0) {
          this.mediaItems[idx].subtitleUrl = tracks[0].url;
          this.mediaItems[idx].subtitleTracks = tracks;
        }
        return tracks;
      } catch (e) {
        hilog.warn(0x0001, 'PrismPlex', 'probe failed: %{public}s', e instanceof Error ? e.message : String(e));
        return [];
      }
    }
    try {
      const slash = item.remotePath.lastIndexOf('/');
      const dirPath = slash > 0 ? item.remotePath.substring(0, slash) : '/';
      const entries = await RemoteSourceClient.listDirectory(source, dirPath);
      const tracks = Formatters.matchSidecarSubtitles(entries, item.fileName || item.remotePath);
      if (tracks.length === 0) {
        return [];
      }
      await this.db.updateMediaItemSubtitles(item.id, tracks[0].url, tracks);
      const idx = this.mediaItems.findIndex(m => m.id === item.id);
      if (idx >= 0) {
        this.mediaItems[idx].subtitleUrl = tracks[0].url;
        this.mediaItems[idx].subtitleTracks = tracks;
      }
      return tracks;
    } catch (_e) {
      return [];
    }
  }

  /**
   * Downloads any remote or Douyin video item to persistent local storage so it can be watched offline,
   * updates its library entry, and optionally exports via system file picker.
   */
  async saveMediaItemOffline(
    item: MediaItem,
    source: MediaSource | undefined,
    exportToSystemPicker: boolean = false,
    onProgress?: (receivedBytes: number) => void
  ): Promise<LocalVideoSaveResult> {
    if (!this.context) {
      return { ok: false, localPath: '', fileSize: 0, exportedUri: '', message: '上下文未就绪', offline: false };
    }
    let playUrl = item.streamUrl;
    try {
      const resolved = await RemoteSourceClient.resolvePlayableStream(item, source);
      playUrl = resolved.streamUrl;
    } catch (_e) {
      // Fallback to item.streamUrl
    }

    let dlUrl = playUrl;
    let tempStreamId = '';
    // 远端 SMB 或 WebDAV/Alist 的 HTTP 流才走本地 Range Proxy；
    // 已离线保存的条目 streamUrl 是沙箱路径，再套代理会把本地路径当远端打开（502）。
    const needsProxy = RemoteSourceClient.needsRangeProxy(playUrl, source);
    if (needsProxy) {
      this.ensureNativeProxy();
      tempStreamId = `dl_${Date.now()}`;
      const proxyCfg = RemoteSourceClient.buildProxyConfig(playUrl, source);
      const proxied = prismNative.registerProxyStream(tempStreamId, proxyCfg);
      if (!proxied) {
        return {
          ok: false,
          localPath: '',
          fileSize: 0,
          exportedUri: '',
          message: '保存失败：本地代理未就绪，无法读取该片源',
          offline: false
        };
      }
      dlUrl = proxied;
    }

    let res: LocalVideoSaveResult;
    try {
      res = await DouyinClient.saveVideoToLocal(dlUrl, item.title, this.context, {
        exportToSystemPicker: exportToSystemPicker,
        fileNameHint: item.fileName || item.remotePath,
        onProgress: onProgress
      });
    } finally {
      if (tempStreamId) {
        try {
          prismNative.unregisterProxyStream(tempStreamId);
        } catch (_e) {
          // Ignore
        }
      }
    }

    if (res.ok && res.localPath && res.offline) {
      item.streamUrl = res.localPath;
      item.fileSize = res.fileSize;
      if (!item.qualityTag.includes('已保存')) {
        item.qualityTag = item.qualityTag ? `${item.qualityTag} · 已保存` : '已离线保存';
      }
      await this.db.upsertMediaItems([item]);
      await this.reloadAllData();
    }
    return res;
  }

  /**
   * 清空离线影库与缓存。离线条目会从影库移除（重新扫描片源可恢复）。
   * 返回按清理前统计估算的释放字节数。
   */
  async clearLocalStorage(): Promise<number> {
    if (!this.context) return 0;
    const ctx = this.context;
    const before = await LocalStorageUsage.collect(ctx);
    const savedDir = `${ctx.filesDir}/saved_videos`;
    const offlineIds: string[] = [];
    for (let i = 0; i < this.mediaItems.length; i++) {
      if (this.mediaItems[i].streamUrl.startsWith(`${savedDir}/`)) {
        offlineIds.push(this.mediaItems[i].id);
      }
    }

    AppStore.removeDirContents(ctx.cacheDir, 0);
    AppStore.removeDirContents(savedDir, 0);
    if (offlineIds.length > 0) {
      await this.db.deleteMediaItems(offlineIds);
      await this.db.deleteWatchHistoryItems(offlineIds);
      await this.reloadAllData();
    }

    const freed = before.offlineBytes + before.cacheBytes;
    hilog.info(0x0001, 'PrismStorage', 'cleared bytes=%{public}d items=%{public}d',
      freed, offlineIds.length);
    return freed;
  }

  /** 只清空目录内容，保留目录本身；不跟随符号链接 */
  private static removeDirContents(dir: string, depth: number): void {
    if (depth > 6 || dir.length < 2) return;
    let names: string[] = [];
    try {
      names = fs.listFileSync(dir);
    } catch (_e) {
      return;
    }
    for (let i = 0; i < names.length; i++) {
      const child = `${dir}/${names[i]}`;
      try {
        const st = fs.lstatSync(child);
        if (st.isSymbolicLink()) {
          fs.unlinkSync(child);
        } else if (st.isDirectory()) {
          AppStore.removeDirContents(child, depth + 1);
          fs.rmdirSync(child);
        } else {
          fs.unlinkSync(child);
        }
      } catch (_e) {
        // 跳过占用中/无权限的文件，继续清理其余内容
      }
    }
  }

  async addRemoteFileToLibrary(source: MediaSource, entry: RemoteFileEntry, siblingSubUrl: string): Promise<MediaItem> {
    const ytId = (source.type === 'youtube' || entry.fullUrl.startsWith('youtube://'))
      ? YouTubeClient.extractVideoId(entry.fullUrl)
      : '';
    if (ytId) {
      const ytItem: MediaItem = {
        id: `${source.id}_yt_${ytId}`,
        sourceId: source.id,
        sourceType: 'youtube',
        remotePath: entry.path,
        streamUrl: `youtube://watch?v=${ytId}`,
        fileName: `${entry.name}.mp4`,
        fileSize: 0,
        mediaType: 'movie',
        seriesKey: `${source.id}_yt_${ytId}`,
        seriesTitle: source.name,
        seasonNo: 1,
        episodeNo: 0,
        title: entry.name,
        originalTitle: '',
        year: 0,
        overview: entry.lastModified || source.name,
        posterUrl: `https://i.ytimg.com/vi/${ytId}/hqdefault.jpg`,
        backdropUrl: `https://i.ytimg.com/vi/${ytId}/maxresdefault.jpg`,
        rating: 0,
        qualityTag: 'YouTube',
        tmdbId: 0,
        durationMs: 0,
        subtitleUrl: siblingSubUrl,
        addedAt: Date.now()
      };
      await this.db.upsertMediaItems([ytItem]);
      await this.reloadAllData();
      return ytItem;
    }

    const parsed = Formatters.parseMediaFilename(entry.name);
    let item: MediaItem = {
      id: `${source.id}_${entry.path}`,
      sourceId: source.id,
      sourceType: source.type,
      remotePath: entry.path,
      streamUrl: entry.fullUrl,
      fileName: entry.name,
      fileSize: entry.size,
      mediaType: source.type === 'iptv' ? 'movie' : parsed.mediaType,
      seriesKey: parsed.mediaType === 'episode' && source.type !== 'iptv'
        ? `${source.id}_${parsed.cleanTitle.toLowerCase()}`
        : `${source.id}_${entry.path}`,
      seriesTitle: source.type === 'iptv' ? source.name : parsed.cleanTitle,
      seasonNo: parsed.seasonNo,
      episodeNo: parsed.episodeNo,
      title: source.type === 'iptv' ? entry.name : parsed.cleanTitle,
      originalTitle: '',
      year: source.type === 'iptv' ? 0 : parsed.year,
      overview: source.type === 'iptv' ? (entry.lastModified || source.name) : '',
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      qualityTag: source.type === 'iptv' ? 'STREAM' : parsed.qualityTag,
      tmdbId: 0,
      durationMs: 0,
      subtitleUrl: siblingSubUrl,
      addedAt: Date.now()
    };
    if (this.settings.tmdbApiKey && source.type !== 'iptv') {
      item = await TmdbScraper.enrichItem(item, this.settings);
    }
    await this.db.upsertMediaItems([item]);
    await this.reloadAllData();
    return item;
  }

  /** 刮削候选搜索（供详情页刮削面板逐条挑选）。 */
  async searchScrapeCandidates(item: MediaItem, query: string): Promise<TmdbCandidate[]> {
    const kind = item.mediaType === 'episode' ? 'tv' : 'movie';
    return TmdbScraper.searchCandidates(this.settings, kind, query);
  }

  /** 应用用户选中的刮削候选并持久化。 */
  async scrapeItemWithCandidate(item: MediaItem, cand: TmdbCandidate): Promise<MediaItem> {
    const enriched = TmdbScraper.applyCandidate(item, this.settings, cand);
    await this.db.upsertMediaItems([enriched]);
    await this.reloadAllData();
    return enriched;
  }

  async saveWatchProgress(record: WatchHistoryRecord): Promise<void> {
    await this.db.saveWatchHistory(record);
    this.watchHistory = await this.db.listWatchHistory();
    await this.refreshCardSnapshot();
  }

  async deleteWatchHistoryItem(itemId: string): Promise<void> {
    await this.db.deleteWatchHistoryItem(itemId);
    this.watchHistory = this.watchHistory.filter(h => h.itemId !== itemId);
    await this.refreshCardSnapshot();
  }

  async clearWatchHistory(): Promise<void> {
    await this.db.clearWatchHistory();
    this.watchHistory = [];
    await this.refreshCardSnapshot();
  }

  getHistoryForItem(itemId: string): WatchHistoryRecord | undefined {
    return this.watchHistory.find(h => h.itemId === itemId);
  }

  getSeriesGroups(): SeriesGroup[] {
    const visible = this.getVisibleMediaItems();
    const map = new Map<string, SeriesGroup>();
    for (let i = 0; i < visible.length; i++) {
      const it = visible[i];
      if (it.mediaType !== 'episode') continue;
      let grp = map.get(it.seriesKey);
      if (!grp) {
        grp = {
          seriesKey: it.seriesKey,
          title: it.seriesTitle || it.title,
          posterUrl: it.posterUrl,
          backdropUrl: it.backdropUrl,
          overview: it.overview,
          year: it.year,
          rating: it.rating,
          tmdbId: it.tmdbId,
          episodes: []
        };
        map.set(it.seriesKey, grp);
      }
      grp.episodes.push(it);
      if (!grp.posterUrl && it.posterUrl) grp.posterUrl = it.posterUrl;
      if (!grp.overview && it.overview) grp.overview = it.overview;
    }
    const groups = Array.from(map.values());
    groups.forEach(g => {
      g.episodes.sort((a, b) => (a.seasonNo !== b.seasonNo ? a.seasonNo - b.seasonNo : a.episodeNo - b.episodeNo));
    });
    return groups;
  }

  handleIncomingFileWant(uri: string): void {
    if (!uri) return;
    const decoded = decodeURIComponent(uri);
    const slash = decoded.lastIndexOf('/');
    const fileName = slash >= 0 ? decoded.substring(slash + 1) : 'external_video.mp4';
    const parsed = Formatters.parseMediaFilename(fileName);
    this.pendingLaunchItem = {
      id: `want_${uri}`,
      sourceId: 'local_device',
      sourceType: 'local',
      remotePath: uri,
      streamUrl: uri,
      fileName,
      fileSize: 0,
      mediaType: parsed.mediaType,
      seriesKey: `want_${parsed.cleanTitle}`,
      seriesTitle: parsed.cleanTitle,
      seasonNo: parsed.seasonNo,
      episodeNo: parsed.episodeNo,
      title: parsed.cleanTitle,
      originalTitle: '',
      year: parsed.year,
      overview: '通过系统“打开方式”直接唤起播放',
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      qualityTag: parsed.qualityTag,
      tmdbId: 0,
      durationMs: 0,
      subtitleUrl: '',
      addedAt: Date.now()
    };
  }
}

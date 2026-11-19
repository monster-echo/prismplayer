import { common } from '@kit.AbilityKit';
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
  RemoteFileEntry,
  SeriesGroup,
  SubtitleTrackOption,
  ThemeMode,
  VaultEntry,
  VaultEntryKind,
  WatchHistoryRecord
} from '../common/Types';
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
  @Trace currentBreakpoint: BreakpointType = 'sm';
  @Trace isLandscape: boolean = false;

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
    if (this.mediaItems.length === 0 && this.sources.length === 0) {
      await this.seedOpenShowcaseLibrary();
    }
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
  }

  hasVaultPin(): boolean {
    return !!this.settings.vaultPinCipher;
  }

  async setVaultPin(newPin: string): Promise<void> {
    const clean = newPin.trim();
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

  async verifyVaultPin(candidate: string): Promise<boolean> {
    if (!this.settings.vaultPinCipher) return false;
    const stored = await CryptoVault.decrypt(this.settings.vaultPinCipher);
    return stored.length > 0 && stored === candidate.trim();
  }

  async unlockVault(pin: string): Promise<boolean> {
    const ok = await this.verifyVaultPin(pin);
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
    opts.maxSelectNumber = 10;
    const uris = await docPicker.select(opts);
    if (!uris || uris.length === 0) return [];

    const imported: MediaItem[] = [];
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      const decoded = decodeURIComponent(uri);
      const slash = decoded.lastIndexOf('/');
      const fileName = slash >= 0 ? decoded.substring(slash + 1) : `local_${i}.mp4`;
      if (!Formatters.isVideoFile(fileName)) continue;

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
        // Non-fatal
      }

      const parsed = Formatters.parseMediaFilename(fileName);
      const qTag = height >= 2160 ? '4K' : (height >= 1080 ? '1080P' : parsed.qualityTag);
      const item: MediaItem = {
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
      imported.push(item);
    }

    if (imported.length > 0) {
      await this.db.upsertMediaItems(imported);
      await this.reloadAllData();
    }
    return imported;
  }

  /**
   * Resolves a Douyin share link or share command, adds it to the library,
   * and optionally downloads the watermark-free MP4 to local device storage.
   */
  async resolveDouyinShareAndImport(shareText: string, saveOfflineNow: boolean = false): Promise<MediaItem> {
    const info = await DouyinClient.resolveShareLink(shareText);
    const item = DouyinClient.toMediaItem(info, 'douyin_share');
    if (saveOfflineNow && this.context) {
      const saved = await DouyinClient.saveVideoToLocal(item.streamUrl, item.title, this.context, false);
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
  async probeSubtitlesForItem(item: MediaItem, source?: MediaSource): Promise<SubtitleTrackOption[]> {
    if (item.subtitleTracks && item.subtitleTracks.length > 0) {
      return item.subtitleTracks;
    }
    if (!source || !item.remotePath || item.remotePath.startsWith('/douyin/')) {
      return [];
    }
    if (source.type === 'youtube' || source.type === 'douyin' || source.type === 'iptv' || source.type === 'local') {
      return [];
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
    exportToSystemPicker: boolean = false
  ): Promise<LocalVideoSaveResult> {
    if (!this.context) {
      return { ok: false, localPath: '', fileSize: 0, exportedUri: '', message: '上下文未就绪' };
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
    // Route SMB, WebDAV/Alist Basic Auth, or insecure TLS streams through local C++ Range Proxy for reliable download
    const needsProxy = playUrl.toLowerCase().startsWith('smb://') ||
      (source !== undefined && (source.type === 'webdav' || source.type === 'alist' || source.type === 'smb'));
    if (needsProxy) {
      this.ensureNativeProxy();
      tempStreamId = `dl_${Date.now()}`;
      const proxyCfg = RemoteSourceClient.buildProxyConfig(playUrl, source);
      const proxied = prismNative.registerProxyStream(tempStreamId, proxyCfg);
      if (proxied) {
        dlUrl = proxied;
      }
    }

    let res: LocalVideoSaveResult;
    try {
      res = await DouyinClient.saveVideoToLocal(dlUrl, item.title, this.context, exportToSystemPicker);
    } finally {
      if (tempStreamId) {
        try {
          prismNative.unregisterProxyStream(tempStreamId);
        } catch (_e) {
          // Ignore
        }
      }
    }

    if (res.ok && res.localPath) {
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
  }

  async deleteWatchHistoryItem(itemId: string): Promise<void> {
    await this.db.deleteWatchHistoryItem(itemId);
    this.watchHistory = this.watchHistory.filter(h => h.itemId !== itemId);
  }

  async clearWatchHistory(): Promise<void> {
    await this.db.clearWatchHistory();
    this.watchHistory = [];
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

  async seedOpenShowcaseLibrary(): Promise<void> {
    const now = Date.now();
    // Legally open Creative Commons Blender Foundation films for immediate playback/testing
    const demoItems: MediaItem[] = [
      {
        id: 'demo_bbb_v2',
        sourceId: 'demo_showcase',
        sourceType: 'webdav',
        remotePath: '/OpenCinema/Big.Buck.Bunny.2008.1080p.mp4',
        streamUrl: 'https://media.w3.org/2010/05/bunny/trailer.mp4',
        fileName: 'Big.Buck.Bunny.2008.1080p.mp4',
        fileSize: 11053871,
        mediaType: 'movie',
        seriesKey: 'demo_bbb_v2',
        seriesTitle: 'Big Buck Bunny',
        seasonNo: 1,
        episodeNo: 0,
        title: '大雄兔 (Big Buck Bunny)',
        originalTitle: 'Big Buck Bunny',
        year: 2008,
        overview: 'Blender 基金会开源动画电影。一只温柔的大兔子在遭遇三只顽皮啮齿动物欺凌后，决定用森林机关展开一场幽默反击。内置 ASS 特效字幕与 C++ Range 流式缓存测试。',
        posterUrl: 'local://poster_bbb',
        backdropUrl: 'local://backdrop_bbb',
        rating: 8.4,
        qualityTag: 'HD · MP4',
        tmdbId: 10378,
        durationMs: 32000,
        subtitleUrl: 'builtin://demo_bbb.ass',
        addedAt: now
      },
      {
        id: 'demo_sintel_v2',
        sourceId: 'demo_showcase',
        sourceType: 'webdav',
        remotePath: '/OpenCinema/Sintel.2010.1080p.mp4',
        streamUrl: 'https://media.w3.org/2010/05/sintel/trailer.mp4',
        fileName: 'Sintel.2010.1080p.mp4',
        fileSize: 4372373,
        mediaType: 'movie',
        seriesKey: 'demo_sintel_v2',
        seriesTitle: 'Sintel',
        seasonNo: 1,
        episodeNo: 0,
        title: '辛特尔 (Sintel)',
        originalTitle: 'Sintel',
        year: 2010,
        overview: 'Blender 基金会第三部开源电影。孤独的女孩 Sintel 踏上跨越雪山与沙漠的漫长旅途，只为寻回曾被她救下的小幼龙 Scales。',
        posterUrl: 'local://poster_sintel',
        backdropUrl: 'local://backdrop_sintel',
        rating: 8.7,
        qualityTag: 'HD · 电影',
        tmdbId: 45745,
        durationMs: 52000,
        subtitleUrl: 'builtin://demo_sintel.srt',
        addedAt: now - 1000
      },
      {
        id: 'demo_bunny_clip_v2',
        sourceId: 'demo_showcase',
        sourceType: 'webdav',
        remotePath: '/OpenCinema/Open.Cinema.Demo.Clip.mp4',
        streamUrl: 'https://media.w3.org/2010/05/video/movie_300.mp4',
        fileName: 'Open.Cinema.Demo.Clip.2012.720p.mp4',
        fileSize: 2757913,
        mediaType: 'movie',
        seriesKey: 'demo_bunny_clip_v2',
        seriesTitle: 'Open Cinema Clip',
        seasonNo: 1,
        episodeNo: 0,
        title: '开源影院测试片 (Demo Clip)',
        originalTitle: 'Open Cinema Demo',
        year: 2012,
        overview: 'W3C 公开标准 MP4 流媒体测试片，用于验证硬解与 FFmpeg 软解引擎切换、倍速播放与画中画自适应。',
        posterUrl: 'local://poster_scifi',
        backdropUrl: 'local://poster_scifi',
        rating: 7.9,
        qualityTag: '720P · MP4',
        tmdbId: 0,
        durationMs: 30000,
        subtitleUrl: '',
        addedAt: now - 2000
      }
    ];
    await this.db.upsertMediaItems(demoItems);
    this.mediaItems = await this.db.listMediaItems();
  }

  getBuiltInDemoSubtitle(subUrl: string): string {
    if (subUrl === 'builtin://demo_bbb.ass') {
      return `[Script Info]
Title: Big Buck Bunny Demo ASS
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,HarmonyOS Sans SC,56,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,2,20,20,36,1
Style: Banner,HarmonyOS Sans SC,44,&H00FF8B5E,&H000000FF,&H00000000,&H80000000,-1,0,8,20,20,24,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:08.00,Banner,,0,0,0,,{\\an8\\b1}PrismPlayer 特效字幕引擎已激活（ASS/SSA 演示）
Dialogue: 0,0:00:09.00,0:00:16.00,Default,,0,0,0,,清晨的森林格外宁静，大雄兔刚刚从洞穴中醒来
Dialogue: 0,0:00:17.00,0:00:25.00,Default,,0,0,0,,可在树梢上，三只调皮的小家伙正计划着恶作剧……`;
    }
    if (subUrl === 'builtin://demo_sintel.srt') {
      return `1
00:00:02,000 --> 00:00:08,000
<b>PrismPlayer SRT 字幕示例</b> · 支持 ±0.1s 延时微调

2
00:00:10,000 --> 00:00:18,000
风雪漫天，她独自穿过群山寻找那条失散的幼龙`;
    }
    return '';
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

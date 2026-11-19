import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ExternalSubtitleTrack,
  MediaItem,
  MediaSource,
  PlayerTrackItem,
  SubtitleCue,
  SubtitleLanguageMode,
  SubtitleStyleValues,
  SUBTITLE_SEARCH_LANGUAGES
} from '../common/Types';
import { Formatters } from '../common/Formatters';
import { AppStore } from './AppStore';
import { BurnSubDetector } from './BurnSubDetector';
import { RemoteSourceClient } from './RemoteSourceClient';
import { SubtitleEngine } from './SubtitleEngine';
import { OnlineSubtitleResult, SubtitleService } from './SubtitleService';

/**
 * Player-owned capabilities the subtitle session cannot implement itself.
 * Registered by PlayerPage on attach, cleared on detach.
 */
export class SubtitleSessionHost {
  isLocalPlayback: () => boolean = () => false;
  getPlaybackDurationMs: () => number = () => 0;
  getCacheDir: () => string = () => '';
  applyEmbeddedTrack: (index: number) => boolean = (_index: number) => false;
  clearEmbeddedTrack: (index: number) => void = (_index: number) => {};
  syncWatchProgress: () => void = () => {};
}

/**
 * Single source of truth for everything subtitle-related in the current playback session.
 *
 * The player owns decoding and rendering; the subtitle screens (hub / tracks / style / sync /
 * online / assist / mask) all read and mutate this one object. This keeps each subtitle screen
 * focused on one responsibility without duplicating state or persistence logic.
 */
@ObservedV2
export class SubtitleSession {
  private static instance: SubtitleSession | null = null;

  static getInstance(): SubtitleSession {
    if (!SubtitleSession.instance) {
      SubtitleSession.instance = new SubtitleSession();
    }
    return SubtitleSession.instance;
  }

  private store: AppStore = AppStore.getInstance();
  private host: SubtitleSessionHost | null = null;
  private mediaSource: MediaSource | undefined = undefined;

  @Trace active: boolean = false;
  @Trace mediaItem: MediaItem | null = null;
  @Trace enabled: boolean = true;
  @Trace externalTracks: ExternalSubtitleTrack[] = [];
  @Trace enabledTrackIds: string[] = [];
  @Trace embeddedTracks: PlayerTrackItem[] = [];
  @Trace embeddedSupported: boolean = true;
  @Trace selectedEmbeddedTrack: number = -1;
  @Trace delayMs: number = 0;
  @Trace fontFp: number = 20;
  @Trace languageMode: SubtitleLanguageMode = 'all';
  @Trace bgEnabled: boolean = true;
  @Trace bgOpacityPercent: number = 35;
  @Trace verticalOffsetVp: number = 0;
  @Trace translateEnabled: boolean = false;
  @Trace ttsEnabled: boolean = false;
  @Trace onlineQuery: string = '';
  @Trace languageFilter: string = 'all';
  @Trace onlineSearching: boolean = false;
  @Trace autoMatching: boolean = false;
  @Trace onlineResults: OnlineSubtitleResult[] = [];
  @Trace onlineFuzzyFallback: boolean = false;
  @Trace maskEnabled: boolean = false;
  @Trace maskYTop: number = 0.78;
  @Trace maskYBottom: number = 0.96;
  @Trace maskConfigured: boolean = false;
  @Trace detectingMask: boolean = false;
  @Trace currentCueText: string = '';

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  attach(
    host: SubtitleSessionHost,
    item: MediaItem,
    source: MediaSource | undefined,
    engineSupportsEmbedded: boolean,
    delayOverride?: number,
    embeddedTrackOverride?: number
  ): void {
    this.resetRuntime();
    this.host = host;
    this.mediaItem = item;
    this.mediaSource = source;
    this.active = true;
    this.embeddedSupported = engineSupportsEmbedded;
    this.onlineQuery = this.buildMediaSearchQuery();

    const s = this.store.settings;
    this.fontFp = s.subtitleFontSizeFp;
    this.languageMode = s.subtitleLanguageMode;
    this.bgEnabled = s.subtitleBgEnabled;
    this.bgOpacityPercent = s.subtitleBgOpacityPercent;
    this.verticalOffsetVp = s.subtitleVerticalOffsetVp;

    const hist = this.store.getHistoryForItem(item.id);
    this.delayMs = 0;
    if (delayOverride !== undefined && delayOverride !== 0) {
      this.delayMs = delayOverride;
    } else if (hist && !hist.finished && hist.subtitleDelayMs !== 0) {
      this.delayMs = hist.subtitleDelayMs;
    }
    this.selectedEmbeddedTrack = embeddedTrackOverride !== undefined
      ? embeddedTrackOverride
      : (hist && !hist.finished ? hist.subtitleTrackIndex : -1);
    if (hist && hist.maskEnabled >= 0) {
      this.maskConfigured = true;
      this.maskEnabled = hist.maskEnabled === 1;
      if (hist.maskYTop >= 0 && hist.maskYTop < 1 && hist.maskYBottom > hist.maskYTop && hist.maskYBottom <= 1) {
        this.maskYTop = hist.maskYTop;
        this.maskYBottom = hist.maskYBottom;
      }
    } else {
      this.maskEnabled = s.burnSubMaskDefault;
    }

    this.loadInitialTracks();
  }

  detach(): void {
    this.active = false;
    this.host = null;
    this.mediaItem = null;
    this.mediaSource = undefined;
    this.resetRuntime();
  }

  private resetRuntime(): void {
    this.externalTracks = [];
    this.enabledTrackIds = [];
    this.embeddedTracks = [];
    this.selectedEmbeddedTrack = -1;
    this.delayMs = 0;
    this.translateEnabled = false;
    this.ttsEnabled = false;
    this.onlineResults = [];
    this.onlineFuzzyFallback = false;
    this.onlineSearching = false;
    this.autoMatching = false;
    this.maskEnabled = false;
    this.maskConfigured = false;
    this.maskYTop = 0.78;
    this.maskYBottom = 0.96;
    this.detectingMask = false;
    this.currentCueText = '';
    SubtitleService.stopSpeaking();
  }

  // ---------------------------------------------------------------------------
  // Track loading / management
  // ---------------------------------------------------------------------------

  private async loadInitialTracks(): Promise<void> {
    const item = this.mediaItem;
    if (!item) return;

    // Older library entries may not carry sidecar subtitle metadata yet: probe lazily and write back.
    if (!(item.subtitleTracks && item.subtitleTracks.length > 0)) {
      const probed = await this.store.probeSubtitlesForItem(item, this.mediaSource);
      if (probed.length > 0) {
        item.subtitleTracks = probed;
      }
    }
    if (this.mediaItem !== item) return;

    if (item.subtitleTracks && item.subtitleTracks.length > 0) {
      const tracks = item.subtitleTracks;
      for (let i = 0; i < tracks.length; i++) {
        const t = tracks[i];
        if (!t.url) continue;
        try {
          const content = await RemoteSourceClient.fetchText(t.url, this.mediaSource);
          if (this.mediaItem !== item) return;
          this.addExternalTrack(SubtitleEngine.parse(content, t.label, t.url));
        } catch (_e) {
          // A single remote sidecar failing must not block the other tracks.
        }
      }
      return;
    }

    const subUrl = item.subtitleUrl;
    if (!subUrl) return;
    await this.loadSubtitleFromUrl(subUrl);
  }

  /** Load a subtitle that was resolved dynamically at playback start (e.g. provider-specific URL). */
  async loadSubtitleFromUrl(url: string): Promise<void> {
    if (!url) return;
    const item = this.mediaItem;
    if (url.startsWith('builtin://')) {
      const content = this.store.getBuiltInDemoSubtitle(url);
      if (content) {
        this.addExternalTrack(SubtitleEngine.parse(content, '内置演示特效字幕', url));
      }
      return;
    }
    try {
      const content = await RemoteSourceClient.fetchText(url, this.mediaSource);
      if (this.mediaItem !== item) return;
      const slash = url.lastIndexOf('/');
      const name = slash >= 0 ? decodeURIComponent(url.substring(slash + 1)) : '外挂字幕';
      this.addExternalTrack(SubtitleEngine.parse(content, name, url));
    } catch (_e) {
      // Non-fatal: playback continues without the sidecar subtitle.
    }
  }

  addExternalTrack(track: ExternalSubtitleTrack): void {
    if (this.externalTracks.some(t => t.id === track.id)) return;
    const next = this.externalTracks.slice();
    next.push(track);
    this.externalTracks = next;
    if (this.enabledTrackIds.indexOf(track.id) < 0) {
      const ids = this.enabledTrackIds.slice();
      ids.push(track.id);
      this.enabledTrackIds = ids;
    }
  }

  toggleTrackEnabled(id: string): void {
    const idx = this.enabledTrackIds.indexOf(id);
    const next = this.enabledTrackIds.slice();
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(id);
    }
    this.enabledTrackIds = next;
  }

  removeExternalTrack(id: string): void {
    this.externalTracks = this.externalTracks.filter(t => t.id !== id);
    this.enabledTrackIds = this.enabledTrackIds.filter(t => t !== id);
  }

  isTrackEnabled(id: string): boolean {
    return this.enabledTrackIds.indexOf(id) >= 0;
  }

  setEmbeddedTracks(tracks: PlayerTrackItem[], supported: boolean): void {
    this.embeddedTracks = tracks;
    this.embeddedSupported = supported;
  }

  selectEmbeddedTrack(index: number): boolean {
    const host = this.host;
    if (!host) return false;
    if (index < 0) {
      this.clearEmbeddedTrack();
      return true;
    }
    const ok = host.applyEmbeddedTrack(index);
    if (ok) {
      this.selectedEmbeddedTrack = index;
      host.syncWatchProgress();
    }
    return ok;
  }

  clearEmbeddedTrack(): void {
    const old = this.selectedEmbeddedTrack;
    this.selectedEmbeddedTrack = -1;
    if (this.host) {
      this.host.clearEmbeddedTrack(old);
      this.host.syncWatchProgress();
    }
  }

  /** Used by the player when restoring a saved track before any user action. */
  markEmbeddedTrackApplied(index: number): void {
    this.selectedEmbeddedTrack = index;
  }

  markEmbeddedTrackUnavailable(): void {
    this.selectedEmbeddedTrack = -1;
  }

  selectedEmbeddedLabel(): string {
    if (this.selectedEmbeddedTrack < 0) return '关闭';
    const found = this.embeddedTracks.filter(t => t.index === this.selectedEmbeddedTrack);
    return found.length > 0 ? found[0].label : `轨道 ${this.selectedEmbeddedTrack}`;
  }

  hasBilingualTrack(): boolean {
    return this.externalTracks.some(t => t.langTag === 'zh-en');
  }

  langBadge(tag: string): string {
    if (tag === 'zh') return '中文';
    if (tag === 'en') return '英文';
    if (tag === 'zh-en') return '双语';
    return '未知';
  }

  // ---------------------------------------------------------------------------
  // Timing
  // ---------------------------------------------------------------------------

  setDelayMs(value: number): void {
    const clamped = Math.max(-60000, Math.min(60000, Math.round(value)));
    this.delayMs = clamped;
    if (this.host) this.host.syncWatchProgress();
  }

  nudgeDelay(deltaMs: number): void {
    this.setDelayMs(this.delayMs + deltaMs);
  }

  delayLabel(): string {
    if (this.delayMs === 0) return '0.0s';
    const abs = Math.abs(this.delayMs / 1000).toFixed(1);
    return this.delayMs > 0 ? `+${abs}s` : `-${abs}s`;
  }

  // ---------------------------------------------------------------------------
  // Appearance
  // ---------------------------------------------------------------------------

  styleValues(): SubtitleStyleValues {
    return {
      fontSizeFp: this.fontFp,
      bgEnabled: this.bgEnabled,
      bgOpacityPercent: this.bgOpacityPercent,
      verticalOffsetVp: this.verticalOffsetVp,
      languageMode: this.languageMode
    };
  }

  applyStyle(style: SubtitleStyleValues, persist: boolean): void {
    this.fontFp = style.fontSizeFp;
    this.bgEnabled = style.bgEnabled;
    this.bgOpacityPercent = style.bgOpacityPercent;
    this.verticalOffsetVp = style.verticalOffsetVp;
    this.languageMode = style.languageMode;
    if (persist) this.commitStyleDefaults();
  }

  previewFontSize(value: number): void {
    this.fontFp = Math.round(value);
  }

  previewBgOpacity(value: number): void {
    this.bgOpacityPercent = Math.round(value);
  }

  previewVerticalOffset(value: number): void {
    this.verticalOffsetVp = Math.round(value);
  }

  setBgEnabled(value: boolean): void {
    this.bgEnabled = value;
    this.commitStyleDefaults();
  }

  setLanguageMode(mode: SubtitleLanguageMode): void {
    this.languageMode = mode;
    this.commitStyleDefaults();
  }

  commitStyleDefaults(): void {
    const style = this.styleValues();
    this.store.saveSubtitleDefaults(style).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'save subtitle defaults failed: %{public}s', e.message);
    });
  }

  /** Called by the settings page so an in-flight playback immediately reflects new defaults. */
  syncStyleFromPreferences(): void {
    const s = this.store.settings;
    this.fontFp = s.subtitleFontSizeFp;
    this.languageMode = s.subtitleLanguageMode;
    this.bgEnabled = s.subtitleBgEnabled;
    this.bgOpacityPercent = s.subtitleBgOpacityPercent;
    this.verticalOffsetVp = s.subtitleVerticalOffsetVp;
  }

  // ---------------------------------------------------------------------------
  // Comprehension assist (translation / TTS)
  // ---------------------------------------------------------------------------

  setTranslateEnabled(value: boolean): void {
    this.translateEnabled = value;
  }

  setTtsEnabled(value: boolean): void {
    this.ttsEnabled = value;
    if (!value) SubtitleService.stopSpeaking();
  }

  // ---------------------------------------------------------------------------
  // Cue generation (called by the player tick)
  // ---------------------------------------------------------------------------

  buildActiveCues(positionMs: number, isPlaying: boolean): SubtitleCue[] {
    if (!this.enabled || this.enabledTrackIds.length === 0) {
      this.updateCurrentCueText('');
      return [];
    }

    let merged: SubtitleCue[] = [];
    for (let i = 0; i < this.externalTracks.length; i++) {
      const trk = this.externalTracks[i];
      if (this.enabledTrackIds.indexOf(trk.id) < 0) continue;
      const found = SubtitleEngine.findActiveCues(trk.cues, positionMs, this.delayMs);
      merged = merged.concat(found);
    }

    let visible = merged;
    if (this.translateEnabled && merged.length > 0) {
      const translated: SubtitleCue[] = [];
      for (let j = 0; j < merged.length; j++) {
        const c = merged[j];
        const cachedZh = SubtitleService.getCachedTranslation(c.text);
        if (!cachedZh) {
          SubtitleService.translateToChinese(c.text);
          translated.push(c);
        } else {
          translated.push({
            index: c.index,
            startMs: c.startMs,
            endMs: c.endMs,
            text: cachedZh === c.text ? c.text : `${cachedZh}\n${c.text}`,
            alignment: c.alignment,
            colorHex: c.colorHex,
            isBold: c.isBold,
            isItalic: c.isItalic,
            layer: c.layer
          });
        }
      }
      visible = translated;
    }

    this.updateCurrentCueTextFromCues(visible);
    if (this.ttsEnabled && visible.length > 0 && isPlaying) {
      const line = visible[0].text.split('\n')[0];
      SubtitleService.speakSubtitle(line);
    }
    return visible;
  }

  private updateCurrentCueTextFromCues(cues: SubtitleCue[]): void {
    if (cues.length === 0) {
      this.updateCurrentCueText('');
      return;
    }
    const lines: string[] = [];
    for (let i = 0; i < cues.length; i++) {
      if (cues[i].text) lines.push(cues[i].text);
    }
    this.updateCurrentCueText(lines.join('\n'));
  }

  private updateCurrentCueText(text: string): void {
    if (this.currentCueText !== text) {
      this.currentCueText = text;
    }
  }

  setEnabled(value: boolean): void {
    this.enabled = value;
    if (!value) this.updateCurrentCueText('');
  }

  // ---------------------------------------------------------------------------
  // Online subtitles
  // ---------------------------------------------------------------------------

  setOnlineQuery(value: string): void {
    this.onlineQuery = value;
  }

  /**
   * Default online query: the clean title parsed from the actual file name.
   * Season/episode is deliberately NOT appended to the query: sources such as SubDL return
   * zero hits for "show S01E02" but many for "show"; the episode token is used for ranking.
   */
  buildMediaSearchQuery(): string {
    const item = this.mediaItem;
    if (!item) return '';
    const parsed = item.fileName ? Formatters.parseMediaFilename(item.fileName) : undefined;
    if (parsed && parsed.cleanTitle && parsed.cleanTitle.length >= 2) {
      return parsed.cleanTitle;
    }
    return (item.seriesTitle || item.title || item.originalTitle || '').trim();
  }

  private resolvedSeasonNo(): number {
    const item = this.mediaItem;
    if (!item) return 0;
    const parsed = item.fileName ? Formatters.parseMediaFilename(item.fileName) : undefined;
    return parsed && parsed.seasonNo > 0 ? parsed.seasonNo : item.seasonNo;
  }

  private resolvedEpisodeNo(): number {
    const item = this.mediaItem;
    if (!item) return 0;
    const parsed = item.fileName ? Formatters.parseMediaFilename(item.fileName) : undefined;
    return parsed && parsed.episodeNo > 0 ? parsed.episodeNo : item.episodeNo;
  }

  /** Human-readable season/episode scope taken from the file name, e.g. "S01E02 · 第 2 集". */
  mediaMatchScopeLabel(): string {
    const item = this.mediaItem;
    if (!item) return '';
    const season = this.resolvedSeasonNo();
    const episode = this.resolvedEpisodeNo();
    if (season > 0 && episode > 0) {
      return `S${this.pad2(season)}E${this.pad2(episode)} · 第 ${episode} 集`;
    }
    const parsed = item.fileName ? Formatters.parseMediaFilename(item.fileName) : undefined;
    const year = parsed && parsed.year > 0 ? parsed.year : item.year;
    return year > 0 ? `${year} 年` : '';
  }

  /** If a user explicitly types a season/episode token, retry with the bare title on zero hits. */
  private simplifySearchQuery(query: string): string {
    let simplified = query.replace(/\s*S\d{1,2}\s*E\d{1,3}\s*$/i, '').trim();
    simplified = simplified.replace(/\s+第\s*\d+\s*[集话]\s*$/, '').trim();
    return simplified;
  }

  resetOnlineQueryToMedia(): void {
    this.onlineQuery = this.buildMediaSearchQuery();
  }

  setLanguageFilter(code: string): void {
    this.languageFilter = code;
  }

  languageFilterLabel(): string {
    const found = SUBTITLE_SEARCH_LANGUAGES.find((opt) => opt.code === this.languageFilter);
    return found ? found.label : '全部语言';
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  async searchOnline(query: string): Promise<number> {
    const clean = (query || '').trim();
    if (!clean || this.onlineSearching) return 0;
    this.onlineSearching = true;
    this.onlineFuzzyFallback = false;
    try {
      const fileName = this.mediaItem ? this.mediaItem.fileName : '';
      const season = this.resolvedSeasonNo();
      const episode = this.resolvedEpisodeNo();
      let effective = clean;
      let results = await SubtitleService.searchAllSubtitles(
        effective,
        fileName,
        this.languageFilter,
        this.store.settings.subdlApiKey,
        season,
        episode
      );
      // Some sources reject "show S01E02" but match "show"; keep the episode token for ranking.
      if (results.length === 0) {
        const simplified = this.simplifySearchQuery(effective);
        if (simplified && simplified !== effective) {
          effective = simplified;
          hilog.info(0x0001, 'PrismSub', 'retry without episode token q=%{public}s', effective);
          results = await SubtitleService.searchAllSubtitles(
            effective,
            fileName,
            this.languageFilter,
            this.store.settings.subdlApiKey,
            season,
            episode
          );
        }
      }
      // Last resort: title-only search; mark results as non-exact so the UI can warn.
      if (results.length === 0 && season > 0 && episode > 0) {
        results = await SubtitleService.searchAllSubtitles(
          effective,
          fileName,
          this.languageFilter,
          this.store.settings.subdlApiKey,
          0,
          0
        );
        this.onlineFuzzyFallback = results.length > 0;
      }
      this.onlineQuery = clean;
      this.onlineResults = results;
      return results.length;
    } finally {
      this.onlineSearching = false;
    }
  }

  /**
   * Best-effort automatic match: filename-derived clean title first, then TMDB's original
   * title for Chinese-scraped entries, then the aggregated source ranking.
   */
  async autoMatchOnline(): Promise<OnlineSubtitleResult | null> {
    if (this.autoMatching) return null;
    const item = this.mediaItem;
    if (!item) return null;
    this.autoMatching = true;
    this.onlineFuzzyFallback = false;
    try {
      const fileName = item.fileName || '';
      let query = (this.onlineQuery || item.title || '').trim();
      if (fileName) {
        const parsed = Formatters.parseMediaFilename(fileName);
        if (parsed.cleanTitle && parsed.cleanTitle.length >= 2) {
          query = parsed.cleanTitle;
        }
      }
      if (this.store.settings.tmdbApiKey) {
        try {
          const cands = await this.store.searchScrapeCandidates(item, query);
          if (cands.length > 0 && cands[0].originalTitle && cands[0].originalTitle.length >= 2) {
            query = cands[0].originalTitle;
          }
        } catch (_e) {
          // TMDB lookup is opportunistic; keep the filename-derived query on failure.
        }
      }
      const season = this.resolvedSeasonNo();
      const episode = this.resolvedEpisodeNo();
      let results = await SubtitleService.searchAllSubtitles(
        query,
        fileName,
        this.languageFilter,
        this.store.settings.subdlApiKey,
        season,
        episode
      );
      if (results.length === 0 && season > 0 && episode > 0) {
        results = await SubtitleService.searchAllSubtitles(
          query,
          fileName,
          this.languageFilter,
          this.store.settings.subdlApiKey,
          0,
          0
        );
        this.onlineFuzzyFallback = results.length > 0;
      }
      this.onlineQuery = query;
      this.onlineResults = results;
      if (results.length === 0) return null;
      await this.mountOnlineSubtitle(results[0]);
      return results[0];
    } finally {
      this.autoMatching = false;
    }
  }

  async mountOnlineSubtitle(result: OnlineSubtitleResult): Promise<ExternalSubtitleTrack> {
    const cacheDir = this.host ? this.host.getCacheDir() : '';
    const text = await SubtitleService.downloadSubtitleText(result.downloadUrl, cacheDir);
    const track = SubtitleEngine.parse(text, `${result.langLabel} · ${result.title}`, result.downloadUrl);
    this.addExternalTrack(track);
    this.enabled = true;
    return track;
  }

  // ---------------------------------------------------------------------------
  // Burned-in subtitle occlusion
  // ---------------------------------------------------------------------------

  setMaskEnabled(value: boolean): void {
    this.maskEnabled = value;
    this.maskConfigured = true;
    if (this.host) this.host.syncWatchProgress();
  }

  setMaskRange(yTop: number, yBottom: number): void {
    this.maskYTop = yTop;
    this.maskYBottom = yBottom;
  }

  commitMask(): void {
    this.maskEnabled = true;
    this.maskConfigured = true;
    if (this.host) this.host.syncWatchProgress();
  }

  canDetectBurnedInSubtitle(): boolean {
    return this.host !== null && this.host.isLocalPlayback();
  }

  async detectBurnedInSubtitle(): Promise<boolean> {
    const item = this.mediaItem;
    const host = this.host;
    if (!item || !host || this.detectingMask || !host.isLocalPlayback()) return false;
    this.detectingMask = true;
    try {
      const res = await BurnSubDetector.detect(item.streamUrl, host.getPlaybackDurationMs());
      if (!res) return false;
      this.maskYTop = res.yTop;
      this.maskYBottom = res.yBottom;
      this.maskEnabled = true;
      this.maskConfigured = true;
      host.syncWatchProgress();
      return true;
    } finally {
      this.detectingMask = false;
    }
  }

  saveMaskAsDefault(): void {
    this.store.saveBurnSubMaskDefault(this.maskEnabled).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'save mask default failed: %{public}s', e.message);
    });
  }

  maskRangeLabel(): string {
    return `顶部 ${Math.round(this.maskYTop * 100)}% · 底部 ${Math.round(this.maskYBottom * 100)}%`;
  }
}

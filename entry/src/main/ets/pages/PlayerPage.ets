import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PiPWindow, window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@kit.InputKit';
import {
  IjkMediaPlayer,
  OnCompletionListener,
  OnErrorListener,
  OnPreparedListener,
  OnVideoSizeChangedListener
} from '@ohos/ijkplayer';
import prismNative from 'libprismplayer.so';
import { playerMenuOptions } from '../common/MenuSurface';
import { AppConstants } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { ThemeManager } from '../common/ThemeManager';
import {
  AspectMode,
  DecoderEngineMode,
  MediaItem,
  MediaSource,
  PlayerLaunchParams,
  PlayerTrackItem,
  SubtitleCue,
  SubtitlePageRoute,
  DecodeRoutingDecision,
} from '../common/Types';
import { SubtitleOverlay } from '../components/SubtitleOverlay';
import { SubtitleMaskBand } from '../components/SubtitleMaskBand';
import { SubtitleAssistPage } from '../components/subtitle/SubtitleAssistPage';
import { SubtitleHubPage } from '../components/subtitle/SubtitleHubPage';
import { SubtitleMaskPage } from '../components/subtitle/SubtitleMaskPage';
import { SubtitleOnlinePage } from '../components/subtitle/SubtitleOnlinePage';
import { SubtitleStylePage } from '../components/subtitle/SubtitleStylePage';
import { SubtitleSyncPage } from '../components/subtitle/SubtitleSyncPage';
import { SubtitleTracksPage } from '../components/subtitle/SubtitleTracksPage';
import { computePictureRect, PictureRect } from '../common/VideoLayout';
import { AppStore } from '../services/AppStore';
import { AVSessionService } from '../services/AVSessionService';
import { MusicPlayerService } from '../services/MusicPlayerService';
import { BurnSubDetector } from '../services/BurnSubDetector';
import { CodecCapability } from '../services/CodecCapability';
import { ContinuePermission } from '../services/ContinuePermission';
import { PcSurfaceService } from '../services/PcSurfaceService';
import { ContinuePayload } from '../services/PlaybackHandoff';
import { ReviewPrompt } from '../services/ReviewPrompt';
import { ShareService } from '../services/ShareService';
import { RemoteSourceClient } from '../services/RemoteSourceClient';
import { SubtitleSession, SubtitleSessionHost } from '../services/SubtitleSession';

interface ResolvedPlaybackUrl {
  url: string;
  isLocalFd: boolean;
}

interface IjkAudioStream {
  streamIndex: number;
  language: string;
  codec: string;
  label: string;
}

interface IjkStreamInfo {
  index?: number;
  type?: string;
  codec_type?: string;
  codec_name?: string;
  language?: string;
}

interface IjkMediaMeta {
  streams?: IjkStreamInfo[];
}

interface IjkMediaInfo {
  audioDecoder?: string;
  videoDecoder?: string;
  meta?: string;
}

@Entry
@ComponentV2
struct PlayerPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local mediaItem: MediaItem | null = null;
  @Local mediaSource: MediaSource | undefined = undefined;

  @Local engineMode: DecoderEngineMode = 'native_hw';
  @Local isPlaying: boolean = false;
  @Local isBuffering: boolean = true;
  @Local positionMs: number = 0;
  @Local durationMs: number = 0;
  @Local videoWidth: number = 1920;
  @Local videoHeight: number = 1080;
  @Local playbackRate: number = 1.0;
  @Local volume: number = 1.0;
  @Local muted: boolean = false;
  @Local screenBrightness: number = 1.0;
  @Local aspectMode: AspectMode = 'fit';

  @Local showControls: boolean = true;
  @Local screenLocked: boolean = false;
  @Local isFullscreen: boolean = false;
  @Local drawerTab: 'none' | 'settings' = 'none';
  @Local subtitlePage: SubtitlePageRoute = 'none';
  @Local showStatsOsd: boolean = false;
  @Local errorBanner: string = '';
  @Local toastText: string = '';
  @Local viewportWidthVp: number = 360;
  @Local viewportHeightVp: number = 780;
  @Local gestureKind: 'none' | 'seek' | 'vol' | 'bright' = 'none';
  @Local gestureLabel: string = '';
  @Local gestureSubLabel: string = '';
  @Local gestureRatio: number = 0;

  @Local tracks: PlayerTrackItem[] = [];
  @Local selectedAudioTrack: number = -1;
  @Local ijkAudioStreams: IjkAudioStream[] = [];
  @Local selectedIjkAudioStream: number = -1;
  @Local activeCues: SubtitleCue[] = [];
  // Burned-in subtitle occlusion drag interaction stays player-owned; values live in SubtitleSession.
  @Local maskAdjusting: boolean = false;
  @Local maskPeeking: boolean = false;

  @Local proxyHitRate: string = '0%';
  @Local proxyBytesText: string = '0 MB';
  @Local proxyResolvedUrl: string = '';
  @Local decodeRouteReason: string = '';
  /** 当前片源推断出的编码 mime，用于设备硬解能力查询与 OSD 展示 */
  @Local activeCodecMime: string = '';

  // ---- 网络评分：实测吞吐 / 内容码率 ----
  /** 实测下行（Mbps），按 1 秒窗口平滑 */
  @Local netMbps: number = 0;
  /** 内容平均码率（Mbps），由文件大小与时长推算 */
  @Local contentMbps: number = 0;
  /** 评分 = 实测 / 码率；<1 表示供不上实时播放 */
  @Local netScore: number = 0;
  @Local netWarningShown: boolean = false;
  private sampleBytes: number = 0;
  private sampleAtMs: number = 0;
  private lowScoreStreak: number = 0;
  /** 滚动窗口 [时刻ms, 累计字节]，用于算 30s 平均吞吐 */
  private netSamples: Array<[number, number]> = [];
  @Local isFavorite: boolean = false;
  @Local playlist: MediaItem[] = [];
  @Local showQueue: boolean = false;

  @Local subtitle: SubtitleSession = SubtitleSession.getInstance();

  private nativePlayerId: number = 0;
  private nativeSurfaceReady: boolean = false;
  private ijkPlayer: IjkMediaPlayer | null = null;
  private ijkContext: object | null = null;
  private activeStreamId: string = '';
  private openedFd: number = -1;
  private startPosMs: number = 0;
  private appliedStartSeek: boolean = false;
  private isSeekingSlider: boolean = false;
  @Local skipIntroSec: number = 0;
  @Local skipOutroSec: number = 0;
  private introSkipped: boolean = false;
  private gestureStartPosMs: number = 0;
  private gestureStartVol: number = 1.0;
  private gestureStartBright: number = 0.8;
  private lastTouchX: number = -1;
  private panZone: 'none' | 'seek' | 'vol' | 'bright' = 'none';
  private enteredInPortrait: boolean = true;
  private resumeAudioTrackIndex: number = -1;
  private appliedResumeTracks: boolean = false;

  private tickTimer: number = -1;
  private hideControlsTimer: number = -1;
  private avSession: AVSessionService = new AVSessionService();
  private nativeController: XComponentController = new XComponentController();
  private ijkController: XComponentController = new XComponentController();
  private pipController: PiPWindow.PiPController | null = null;
  private pipActive: boolean = false;
  private pcSurfaceShown: boolean = false;
  private lastPcTaskAt: number = 0;
  /** 页面退出后禁止再往系统栏写数据，否则退出播放页会留下一个点不掉的图标。 */
  private pageActive: boolean = true;

  aboutToAppear(): void {
    ThemeManager.setPlayerImmersive(true);
    this.skipIntroSec = this.store.settings.autoSkipIntroSec;
    this.skipOutroSec = this.store.settings.autoSkipOutroSec;
    this.introSkipped = false;
    this.enteredInPortrait = !this.store.isLandscape;
    // 视频与音乐互斥：起播视频前先停掉音乐，避免两路声音叠在一起
    MusicPlayerService.getInstance().pause(false);

    const rawParams = this.getUIContext().getRouter().getParams() as PlayerLaunchParams | undefined;
    if (rawParams && rawParams.item) {
      if (rawParams.item.mediaType === 'track') {
        this.getUIContext().getRouter().replaceUrl({
          url: 'pages/MusicPlayerPage',
          params: { item: rawParams.item, queue: [rawParams.item] }
        });
        return;
      }
      this.mediaItem = rawParams.item;
      this.mediaSource = rawParams.source;
      this.startPosMs = rawParams.startPositionMs || 0;
      this.durationMs = rawParams.item.durationMs || 0;
      this.isFavorite = rawParams.item.isFavorite === true;
      this.playlist = rawParams.playlist && rawParams.playlist.length > 0 ? rawParams.playlist : [];
    }
    if (this.mediaItem) {
      const codecMime: string = CodecCapability.hintMime(this.mediaItem);
      const route: DecodeRoutingDecision = Formatters.selectDecodeEngine(
        this.mediaItem,
        this.store.settings.preferHardwareDecode,
        this.store.settings.hardwareSupportedFormats,
        codecMime,
        (mime: string) => CodecCapability.supportsHardware(mime)
      );
      this.engineMode = route.engine;
      this.decodeRouteReason = route.reason;
      this.activeCodecMime = codecMime;
    } else {
      this.engineMode = this.store.settings.preferHardwareDecode ? 'native_hw' : 'ffmpeg_sw';
    }
    if (this.mediaItem && this.mediaItem.sourceType === 'bilibili') {
      // B 站 CDN 校验 Referer，只有 ijk 可注入自定义头，强制软解引擎
      this.engineMode = 'ffmpeg_sw';
    }

    // Launch params only override subtitle state when explicitly meaningful; the session
    // falls back to the watch record (delay / embedded track / mask) on its own.
    let initialSubtitleDelay: number | undefined = undefined;
    let initialSubtitleTrack: number | undefined = undefined;
    if (rawParams) {
      this.resumeAudioTrackIndex = rawParams.audioTrackIndex !== undefined ? rawParams.audioTrackIndex : -1;
      if (rawParams.subtitleTrackIndex !== undefined && rawParams.subtitleTrackIndex >= 0) {
        initialSubtitleTrack = rawParams.subtitleTrackIndex;
      }
      if (rawParams.subtitleDelayMs !== undefined && rawParams.subtitleDelayMs !== 0) {
        initialSubtitleDelay = rawParams.subtitleDelayMs;
      }
      if (rawParams.playbackRate !== undefined && rawParams.playbackRate > 0) {
        this.playbackRate = rawParams.playbackRate;
      }
    }
    // Resume memory: fall back to the saved watch record for audio track and playback rate.
    if (this.mediaItem) {
      const hist = this.store.getHistoryForItem(this.mediaItem.id);
      if (hist && !hist.finished) {
        this.resumeAudioTrackIndex = this.resumeAudioTrackIndex >= 0 ? this.resumeAudioTrackIndex : hist.audioTrackIndex;
        if (!(rawParams && rawParams.playbackRate !== undefined) && hist.playbackRate > 0) {
          this.playbackRate = hist.playbackRate;
        }
      }
      this.attachSubtitleSession(initialSubtitleDelay, initialSubtitleTrack);
    }

    this.store.ensureNativeProxy();
    this.startTickLoop();
    this.scheduleHideControls();
    // 播放页是唯一能解释「可能接到别的设备上看」这句话的上下文，接续权限只在这里问一次
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (ctx) ContinuePermission.ensure(ctx, this.store).catch(() => {});
    } catch (_e) {
      // Ignore: permission is optional for local playback
    }
    this.syncLivePlayback();
  }

  private attachSubtitleSession(delayOverride: number | undefined, trackOverride: number | undefined): void {
    if (!this.mediaItem) return;
    const host = new SubtitleSessionHost();
    host.isLocalPlayback = (): boolean => this.isLocalPlayback();
    host.getPlaybackDurationMs = (): number => this.durationMs;
    host.getCacheDir = (): string => {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      return ctx ? ctx.cacheDir : '';
    };
    host.applyEmbeddedTrack = (index: number): boolean => this.applyEmbeddedTrackSelection(index);
    host.clearEmbeddedTrack = (index: number): void => this.clearEmbeddedTrackSelection(index);
    host.syncWatchProgress = (): void => this.persistProgressNow();
    this.subtitle.attach(
      host,
      this.mediaItem,
      this.mediaSource,
      this.engineMode === 'native_hw',
      delayOverride,
      trackOverride
    );
    this.activeCues = [];
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.stopTickLoop();
    if (this.hideControlsTimer >= 0) {
      clearTimeout(this.hideControlsTimer);
      this.hideControlsTimer = -1;
    }
    this.persistProgressNow();
    this.teardownPlayers();
    this.subtitle.detach();
    this.avSession.release();
    this.releasePip();
    this.hidePcSurface();
    this.store.setLivePlayback(null);
    this.setWindowKeepScreenOn(false);
    this.restoreWindowDefaults();
  }

  private restoreWindowDefaults(): void {
    ThemeManager.setPlayerImmersive(false);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win) => {
        win.setWindowBrightness(-1).catch(() => {});
        win.setWindowLayoutFullScreen(false).catch(() => {});
        // 重新启用系统栏会把栏颜色刷回默认值，所以要在它落地之后再按主题上色
        win.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
          ThemeManager.restoreChrome();
          setTimeout(() => ThemeManager.restoreChrome(), 120);
        }).catch(() => {
          ThemeManager.restoreChrome();
        });
        if (this.store.currentBreakpoint === 'sm' || this.store.currentBreakpoint === 'md') {
          win.setPreferredOrientation(
            this.enteredInPortrait ? window.Orientation.PORTRAIT : window.Orientation.UNSPECIFIED
          ).catch(() => {});
        }
      });
    } catch (_e) {
      // Ignore
    }
  }

  private applyBrightness(level: number): void {
    this.screenBrightness = Math.max(0.05, Math.min(1.0, level));
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win) => {
        // Software overlay dimmer guarantees immediate preview on emulators; window brightness sets panel luminance on devices
        win.setWindowBrightness(Math.max(0.05, this.screenBrightness)).catch(() => {});
      });
    } catch (_e) {
      // Ignore
    }
  }

  private setWindowKeepScreenOn(on: boolean): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win) => {
        win.setWindowKeepScreenOn(on);
      });
    } catch (_e) {
      // Ignore
    }
  }

  private toggleFullscreen(): void {
    this.isFullscreen = !this.isFullscreen;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win) => {
        if (this.store.currentBreakpoint === 'lg' || this.store.currentBreakpoint === 'xl') {
          if (this.isFullscreen) win.maximize();
          else win.recover();
        } else {
          win.setWindowLayoutFullScreen(this.isFullscreen).catch(() => {});
          win.setWindowSystemBarEnable(this.isFullscreen ? [] : ['status', 'navigation']).catch(() => {});
          win.setPreferredOrientation(
            this.isFullscreen
              ? window.Orientation.LANDSCAPE
              : (this.enteredInPortrait ? window.Orientation.PORTRAIT : window.Orientation.UNSPECIFIED)
          ).catch(() => {});
        }
      });
    } catch (_e) {
      // Ignore
    }
    this.showBriefToast(this.isFullscreen ? '已切换横屏全屏' : '已退出全屏');
  }

  private showBriefToast(msg: string): void {
    this.toastText = msg;
    setTimeout(() => {
      if (this.toastText === msg) {
        this.toastText = '';
      }
    }, 1800);
  }

  private scheduleHideControls(): void {
    if (this.hideControlsTimer >= 0) {
      clearTimeout(this.hideControlsTimer);
    }
    this.hideControlsTimer = setTimeout(() => {
      if (this.isPlaying && this.drawerTab === 'none') {
        this.showControls = false;
      }
    }, 3500);
  }

  private wakeControls(): void {
    this.showControls = true;
    this.scheduleHideControls();
  }

  private async resolvePlaybackUrl(): Promise<ResolvedPlaybackUrl> {
    if (!this.mediaItem) return { url: '', isLocalFd: false };
    let rawUrl = this.mediaItem.streamUrl;
    if (rawUrl.startsWith('file://') || rawUrl.startsWith('content://') || rawUrl.startsWith('/')) {
      return { url: rawUrl, isLocalFd: true };
    }

    const dynamicResolved = await RemoteSourceClient.resolvePlayableStream(this.mediaItem, this.mediaSource);
    rawUrl = dynamicResolved.streamUrl;
    if (dynamicResolved.subtitleUrl && this.subtitle.externalTracks.length === 0) {
      this.subtitle.loadSubtitleFromUrl(dynamicResolved.subtitleUrl);
    }

    // HLS (.m3u8) playlists contain relative segment URLs so players must fetch them directly from origin
    const lower = rawUrl.toLowerCase();
    if (lower.includes('.m3u8') || dynamicResolved.qualityTag === 'HLS') {
      return { url: rawUrl, isLocalFd: false };
    }
    if (this.mediaItem.sourceType === 'bilibili') {
      return { url: rawUrl, isLocalFd: false };
    }

    // Route progressive network / SMB / Plex / Emby / S3 / WebDAV / Alist URL through C++ Range-Caching Proxy
    const streamId = `s_${Date.now()}`;
    this.activeStreamId = streamId;
    const proxyCfg = RemoteSourceClient.buildProxyConfig(rawUrl, this.mediaSource);
    const proxied = prismNative.registerProxyStream(streamId, proxyCfg);
    return { url: proxied || rawUrl, isLocalFd: false };
  }

  private teardownPlayers(): void {
    if (this.nativePlayerId > 0) {
      try {
        prismNative.stopPlayer(this.nativePlayerId);
        prismNative.destroyPlayer(this.nativePlayerId);
      } catch (_e) {
        // Ignore
      }
      this.nativePlayerId = 0;
    }
    if (this.ijkPlayer) {
      try {
        this.ijkPlayer.stop();
        this.ijkPlayer.release();
      } catch (_e) {
        // Ignore
      }
      this.ijkPlayer = null;
    }
    if (this.activeStreamId) {
      try {
        prismNative.unregisterProxyStream(this.activeStreamId);
      } catch (_e) {
        // Ignore
      }
      this.activeStreamId = '';
    }
    if (this.openedFd >= 0) {
      try {
        fs.closeSync(this.openedFd);
      } catch (_e) {
        // Ignore
      }
      this.openedFd = -1;
    }
  }

  /** 日志用源标识：去掉账号密码与 query，只留 host + 文件名 */
  private sourceTag(): string {
    const item = this.mediaItem;
    if (!item || !item.streamUrl) return 'none';
    const raw = item.streamUrl;
    let rest = raw;
    const scheme = raw.indexOf('://');
    if (scheme >= 0) {
      rest = raw.substring(scheme + 3);
    }
    const at = rest.lastIndexOf('@');
    if (at >= 0) {
      rest = rest.substring(at + 1);
    }
    const slash = rest.indexOf('/');
    const host = slash >= 0 ? rest.substring(0, slash) : rest;
    const path = slash >= 0 ? rest.substring(slash) : '';
    const q = path.indexOf('?');
    const clean = q >= 0 ? path.substring(0, q) : path;
    const seg = clean.substring(clean.lastIndexOf('/') + 1);
    return seg ? `${host}/${seg}` : host;
  }

  private sanitize(msg: string): string {
    return msg.replace(/\/\/[^@\/\s]*@/g, '//').slice(0, 200);
  }

  /** 仅剧集生效：片头自动跳过一次；片尾只提示不自动跳。 */
  private tickSkip(pos: number): void {
    if (!this.mediaItem || this.mediaItem.mediaType !== 'episode') return;
    if (this.introSkipped || this.skipIntroSec <= 0 || this.durationMs <= 0) return;
    if (this.isSeekingSlider) return;
    const end = this.skipIntroSec * 1000;
    if (pos > 800 && pos < end - 400) {
      this.introSkipped = true;
      hilog.info(0x0001, 'PrismPlay', 'skip intro: %{public}d -> %{public}d ms src=%{public}s',
        pos, end, this.sourceTag());
      this.seekTo(end);
    }
  }

  private showOutroSkip(): boolean {
    if (!this.mediaItem || this.mediaItem.mediaType !== 'episode') return false;
    if (this.skipOutroSec <= 0 || this.durationMs <= 0) return false;
    const start = this.durationMs - this.skipOutroSec * 1000;
    return this.positionMs >= start && this.positionMs < this.durationMs - 800;
  }

  private async applySkip(intro: number, outro: number): Promise<void> {
    this.skipIntroSec = intro;
    this.skipOutroSec = outro;
    this.introSkipped = false;
    await this.store.saveSkipDefaults(intro, outro);
  }

  private async startNativeEngine(): Promise<void> {
    if (!this.mediaItem || !this.nativeSurfaceReady) return;
    this.teardownPlayers();
    this.errorBanner = '';
    this.isBuffering = true;
    this.appliedStartSeek = false;

    let resolved: ResolvedPlaybackUrl;
    try {
      resolved = await this.resolvePlaybackUrl();
    } catch (e) {
      this.isBuffering = false;
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'PrismPlay', 'resolve failed engine=native msg=%{public}s src=%{public}s',
        this.sanitize(msg), this.sourceTag());
      this.errorBanner = Formatters.toFriendlyError(msg, true);
      return;
    }

    const pid = prismNative.createPlayer();
    this.nativePlayerId = pid;
    prismNative.bindSurface(pid, 'prism_video_surface');
    prismNative.setPlayerEventCallback(pid, (ev) => {
      if (this.nativePlayerId !== pid) return;
      if (ev.type === 'state') {
        // 2: PREPARED, 3: PLAYING, 4: PAUSED, 6: COMPLETED
        if (ev.state === 2) {
          this.isBuffering = false;
          if (this.startPosMs > 2000 && !this.appliedStartSeek) {
            this.appliedStartSeek = true;
            prismNative.seekPlayer(pid, this.startPosMs, 2);
          }
          prismNative.playPlayer(pid);
          if (this.playbackRate !== 1.0) {
            prismNative.setPlayerRate(pid, this.playbackRate);
          }
          this.refreshNativeTracks();
          this.applyResumeTrackSelection();
        } else if (ev.state === 3) {
          this.isPlaying = true;
          this.isBuffering = false;
          this.setWindowKeepScreenOn(true);
          this.syncAVSession();
          this.syncLivePlayback();
          this.syncPcSurface();
        } else if (ev.state === 4 || ev.state === 5) {
          this.isPlaying = false;
          this.setWindowKeepScreenOn(false);
          this.syncAVSession();
          this.syncLivePlayback();
          this.persistProgressNow();
          this.syncPcSurface();
        } else if (ev.state === 6) {
          this.isPlaying = false;
          this.persistProgressNow(true);
          this.onPlaybackCompleted();
        }
      } else if (ev.type === 'position' && !this.isSeekingSlider) {
        this.positionMs = ev.positionMs || 0;
      } else if (ev.type === 'duration') {
        this.durationMs = ev.durationMs || this.durationMs;
      } else if (ev.type === 'resolution') {
        this.videoWidth = ev.width || this.videoWidth;
        this.videoHeight = ev.height || this.videoHeight;
      } else if (ev.type === 'buffering') {
        this.isBuffering = ev.bufferingType === 1;
      } else if (ev.type === 'tracksReady') {
        this.refreshNativeTracks();
      } else if (ev.type === 'error') {
        this.isBuffering = false;
        this.isPlaying = false;
        hilog.error(0x0001, 'PrismPlay', 'native error code=%{public}d msg=%{public}s src=%{public}s pos=%{public}d',
          ev.errorCode || 0, this.sanitize(ev.errorMsg || ''), this.sourceTag(), this.positionMs);
        this.showBriefToast('正在切换至兼容解码模式...');
        this.switchEngine('ffmpeg_sw');
      }
    });

    if (resolved.isLocalFd) {
      try {
        const f = fs.openSync(resolved.url, fs.OpenMode.READ_ONLY);
        const st = fs.statSync(f.fd);
        this.openedFd = f.fd;
        prismNative.setFdSource(pid, f.fd, 0, st.size);
      } catch (e) {
        hilog.error(0x0001, 'PrismPlay', 'open local fd failed msg=%{public}s src=%{public}s',
          this.sanitize(e instanceof Error ? e.message : String(e)), this.sourceTag());
        this.errorBanner = '无法打开本地视频文件';
        return;
      }
    } else {
      prismNative.setUrlSource(pid, resolved.url);
    }

    prismNative.preparePlayer(pid);
    this.startAVSession();
  }

  private async startIjkEngine(): Promise<void> {
    if (!this.mediaItem || !this.ijkContext) return;
    this.teardownPlayers();
    this.errorBanner = '';
    this.isBuffering = true;
    this.appliedStartSeek = false;

    let resolved: ResolvedPlaybackUrl;
    try {
      resolved = await this.resolvePlaybackUrl();
    } catch (e) {
      this.isBuffering = false;
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'PrismPlay', 'resolve failed engine=ijk msg=%{public}s src=%{public}s',
        this.sanitize(msg), this.sourceTag());
      this.errorBanner = Formatters.toFriendlyError(msg, true);
      return;
    }

    const ijk = new IjkMediaPlayer('ijk_video_surface');
    ijk.setContext(this.ijkContext, 'ijk_video_surface');
    ijk.native_setup();
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'opensles', '0');
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '1');
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'fastseek', '1');
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'overlay-format', '842225234');
    // ijk requires soundtouch for variable-speed playback; setSpeed expects a "2f" string.
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'soundtouch', '1');
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'reconnect', '1');
    if (this.mediaItem && this.mediaItem.sourceType === 'bilibili') {
      ijk.setOption(
        IjkMediaPlayer.OPT_CATEGORY_FORMAT,
        'headers',
        'Referer: https://www.bilibili.com/\r\nUser-Agent: Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) Mobile Safari/537.36'
      );
    }
    ijk.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'timeout', '10000000');

    // 本机源给的是绝对路径；FFmpeg 只认 file:// URI，直接传路径会报 -10000
    ijk.setDataSource(resolved.url.startsWith('/') ? `file://${resolved.url}` : resolved.url);

    const onPrepared: OnPreparedListener = {
      onPrepared: () => {
        this.isBuffering = false;
        this.durationMs = ijk.getDuration() || this.durationMs;
        if (this.startPosMs > 2000 && !this.appliedStartSeek) {
          this.appliedStartSeek = true;
          ijk.seekTo(`${Math.round(this.startPosMs)}`);
        }
        ijk.start();
        this.isPlaying = true;
        if (this.playbackRate !== 1.0) {
          ijk.setSpeed(`${this.playbackRate}f`);
        }
        this.refreshIjkAudioStreams();
        this.setWindowKeepScreenOn(true);
        this.syncAVSession();
        this.syncLivePlayback();
        this.syncPcSurface();
      }
    };
    const onVideoSize: OnVideoSizeChangedListener = {
      onVideoSizeChanged: (w: number, h: number) => {
        if (w > 0 && h > 0) {
          this.videoWidth = w;
          this.videoHeight = h;
        }
      }
    };
    const onComplete: OnCompletionListener = {
      onCompletion: () => {
        this.isPlaying = false;
        this.persistProgressNow(true);
        this.onPlaybackCompleted();
      }
    };
    const onError: OnErrorListener = {
      onError: (what: number, extra: number) => {
        this.isBuffering = false;
        this.isPlaying = false;
        const isRemote = !!(this.mediaItem && this.mediaItem.streamUrl.startsWith('http'));
        hilog.error(0x0001, 'PrismPlay', 'ijk onError what=%{public}d extra=%{public}d src=%{public}s pos=%{public}d',
          what, extra, this.sourceTag(), this.positionMs);
        this.errorBanner = Formatters.toFriendlyError(`what=${what}, extra=${extra}`, isRemote);
      }
    };

    ijk.setOnPreparedListener(onPrepared);
    ijk.setOnVideoSizeChangedListener(onVideoSize);
    ijk.setOnCompletionListener(onComplete);
    ijk.setOnErrorListener(onError);
    ijk.setMessageListener();
    ijk.prepareAsync();
    this.ijkPlayer = ijk;
    this.startAVSession();
  }

  private switchEngine(target: DecoderEngineMode): void {
    if (this.engineMode === target && ((target === 'native_hw' && this.nativePlayerId > 0) || (target === 'ffmpeg_sw' && this.ijkPlayer !== null))) {
      return;
    }
    this.startPosMs = this.positionMs;
    this.engineMode = target;
    this.showBriefToast(target === 'native_hw' ? '已切换至系统硬件解码' : '已切换至 FFmpeg 软解引擎');
    if (target === 'native_hw') {
      this.startNativeEngine();
    } else {
      this.startIjkEngine();
    }
  }

  private refreshNativeTracks(): void {
    if (this.nativePlayerId <= 0) return;
    try {
      const nativeTracks = prismNative.getPlayerTracks(this.nativePlayerId);
      const list: PlayerTrackItem[] = [];
      for (let i = 0; i < nativeTracks.length; i++) {
        const t = nativeTracks[i];
        const kind = t.trackType === 0 ? 'audio' : (t.trackType === 1 ? 'video' : 'subtitle');
        const lang = t.language || 'und';
        const title = t.title || (kind === 'audio' ? `音轨 ${i + 1}` : `轨道 ${i + 1}`);
        list.push({
          index: t.index,
          kind,
          label: `${title} (${lang})`,
          language: lang,
          codec: t.mimeType || '',
          details: kind === 'audio' && t.channels > 0 ? `${t.channels}ch · ${t.sampleRate}Hz` : ''
        });
      }
      this.tracks = list;
      this.subtitle.setEmbeddedTracks(list.filter(t => t.kind === 'subtitle'), this.engineMode === 'native_hw');
    } catch (_e) {
      // Ignore on devices where track metadata is restricted
    }
  }

  // One-shot: re-apply the audio / embedded-subtitle track saved in watch history
  private applyResumeTrackSelection(): void {
    if (this.appliedResumeTracks || this.nativePlayerId <= 0) return;
    this.appliedResumeTracks = true;
    if (this.resumeAudioTrackIndex >= 0) {
      const found = this.tracks.filter(t => t.kind === 'audio' && t.index === this.resumeAudioTrackIndex);
      if (found.length > 0 && prismNative.selectPlayerTrack(this.nativePlayerId, this.resumeAudioTrackIndex) === 0) {
        this.selectedAudioTrack = this.resumeAudioTrackIndex;
      }
    }
    const desiredSubtitle = this.subtitle.selectedEmbeddedTrack;
    if (desiredSubtitle >= 0) {
      const found = this.tracks.filter(t => t.kind === 'subtitle' && t.index === desiredSubtitle);
      if (found.length > 0 && prismNative.selectPlayerTrack(this.nativePlayerId, desiredSubtitle) === 0) {
        this.subtitle.markEmbeddedTrackApplied(desiredSubtitle);
      } else {
        this.subtitle.markEmbeddedTrackUnavailable();
      }
    }
  }

  private refreshIjkAudioStreams(): void {
    const ijk = this.ijkPlayer;
    if (!ijk) return;
    const list: IjkAudioStream[] = [];
    try {
      const info = ijk.getMediaInfo() as IjkMediaInfo;
      const meta = JSON.parse(info.meta || '{}') as IjkMediaMeta;
      const streams = meta.streams || [];
      for (let i = 0; i < streams.length; i++) {
        const st = streams[i];
        const type = st.type || st.codec_type || '';
        if (type !== 'audio') continue;
        const lang = st.language || 'und';
        const codec = st.codec_name || '';
        list.push({
          streamIndex: typeof st.index === 'number' ? st.index : i,
          language: lang,
          codec,
          label: `音轨 ${list.length + 1} · ${codec}${lang !== 'und' ? ` (${lang})` : ''}`
        });
      }
    } catch (_e) {
      // Meta layout differs across ijk builds; fall back to the default-audio hint
    }
    this.ijkAudioStreams = list;
  }

  private selectIjkAudioStream(streamIndex: number): void {
    const ijk = this.ijkPlayer;
    if (!ijk) return;
    try {
      ijk.selectTrack(`${streamIndex}`);
      this.selectedIjkAudioStream = streamIndex;
      const found = this.ijkAudioStreams.filter(s => s.streamIndex === streamIndex);
      this.showBriefToast(`已切换音轨：${found.length > 0 ? found[0].label : streamIndex}`);
    } catch (_e) {
      this.showBriefToast('切换音轨失败');
    }
  }

  /** Host callback: actually switch the native embedded subtitle track. */
  private applyEmbeddedTrackSelection(index: number): boolean {
    if (this.nativePlayerId <= 0) return false;
    const ok = prismNative.selectPlayerTrack(this.nativePlayerId, index) === 0;
    if (ok) {
      const found = this.tracks.filter(t => t.kind === 'subtitle' && t.index === index);
      this.showBriefToast(`已选择内嵌字幕轨：${found.length > 0 ? found[0].label : index}`);
    }
    return ok;
  }

  /** Host callback: close the native embedded subtitle track. */
  private clearEmbeddedTrackSelection(index: number): void {
    if (this.nativePlayerId <= 0) return;
    if (index >= 0) {
      try {
        prismNative.deselectPlayerTrack(this.nativePlayerId, index);
      } catch (_e) {
        // Ignore deselect errors
      }
    }
    this.showBriefToast('已关闭内嵌字幕');
  }

  private togglePlayPause(): void {
    if (this.engineMode === 'native_hw' && this.nativePlayerId > 0) {
      if (this.isPlaying) {
        prismNative.pausePlayer(this.nativePlayerId);
        this.isPlaying = false;
      } else {
        prismNative.playPlayer(this.nativePlayerId);
        this.isPlaying = true;
      }
    } else if (this.engineMode === 'ffmpeg_sw' && this.ijkPlayer) {
      try {
        if (this.isPlaying) {
          this.ijkPlayer.pause();
          this.isPlaying = false;
        } else {
          this.ijkPlayer.start();
          this.isPlaying = true;
        }
      } catch (e) {
        hilog.error(0x0001, 'PrismPip', 'ijk toggle failed: %{public}s', JSON.stringify(e));
      }
    }
    this.wakeControls();
    this.syncAVSession();
    this.syncLivePlayback();
  }

  private seekTo(targetMs: number): void {
    const clamped = Math.max(0, this.durationMs > 0 ? Math.min(this.durationMs, targetMs) : targetMs);
    this.positionMs = clamped;
    hilog.info(0x0001, 'PrismSeek', 'seekTo %{public}d engine=%{public}s', Math.round(clamped), this.engineMode);
    if (this.engineMode === 'native_hw' && this.nativePlayerId > 0) {
      prismNative.seekPlayer(this.nativePlayerId, Math.round(clamped), 2);
    } else if (this.engineMode === 'ffmpeg_sw' && this.ijkPlayer) {
      this.ijkPlayer.seekTo(`${Math.round(clamped)}`);
    }
    this.syncAVSession();
    this.syncLivePlayback();
  }

  private hasAudioChoices(): boolean {
    if (this.engineMode === 'native_hw') {
      return this.tracks.filter(t => t.kind === 'audio').length > 0;
    }
    return this.ijkAudioStreams.length > 0;
  }

  private setRate(rate: number): void {
    const clamped = Math.max(0.5, Math.min(3.0, Number(rate.toFixed(2))));
    this.playbackRate = clamped;
    if (this.engineMode === 'native_hw' && this.nativePlayerId > 0) {
      prismNative.setPlayerRate(this.nativePlayerId, clamped);
    } else if (this.engineMode === 'ffmpeg_sw' && this.ijkPlayer) {
      this.ijkPlayer.setSpeed(`${clamped}f`);
      hilog.info(0x0001, 'PrismRate', 'ijk speed requested=%{public}s actual=%{public}s', `${clamped}`, `${this.ijkPlayer.getSpeed()}`);
    }
    this.showBriefToast(`倍速 ${clamped}x`);
  }

  private applyVolume(vol: number): void {
    const clamped = Math.max(0, Math.min(1, vol));
    this.volume = clamped;
    const effective = this.muted ? 0 : clamped;
    if (this.engineMode === 'native_hw' && this.nativePlayerId > 0) {
      prismNative.setPlayerVolume(this.nativePlayerId, effective);
    } else if (this.engineMode === 'ffmpeg_sw' && this.ijkPlayer) {
      this.ijkPlayer.setVolume(`${effective}`, `${effective}`);
    }
  }

  private startTickLoop(): void {
    this.stopTickLoop();
    this.tickTimer = setInterval(() => {
      if (this.engineMode === 'ffmpeg_sw' && this.ijkPlayer && this.isPlaying && !this.isSeekingSlider) {
        const pos = this.ijkPlayer.getCurrentPosition();
        if (pos >= 0) this.positionMs = pos;
        const dur = this.ijkPlayer.getDuration();
        if (dur > 0) this.durationMs = dur;
      }

      this.tickSkip(this.positionMs);
      this.activeCues = this.subtitle.buildActiveCues(this.positionMs, this.isPlaying);

      if (this.activeStreamId) {
        try {
          const st = prismNative.getProxyStats(this.activeStreamId);
          const totalReq = st.cacheHits + st.cacheMisses;
          const pct = totalReq > 0 ? Math.round((st.cacheHits / totalReq) * 100) : 0;
          this.proxyHitRate = `${pct}% (${st.cacheHits}/${totalReq})`;
          this.proxyBytesText = Formatters.formatBytes(st.bytesServed);
          this.proxyResolvedUrl = st.resolvedUrl;
          this.updateNetworkScore(st.bytesServed, st.totalSize);
        } catch (_e) {
          // Ignore
        }
      }
    }, 150);
  }

  private stopTickLoop(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  /**
   * 网络评分 = 实测下行 / 内容平均码率。
   *
   * 采样口径：代理累计 bytesServed 的 1 秒增量，做 0.6/0.4 指数平滑。
   * 播放器被喂饱时该值≈码率（1.0 上下），被饿住时才会掉到 1 以下，
   * 因此 <1 持续 3 秒即判定为「供不上实时播放」，给用户一次性提示。
   */
  private updateNetworkScore(bytes: number, totalSize: number): void {
    const now = Date.now();
    if (this.sampleAtMs === 0 || bytes < this.sampleBytes) {
      this.sampleBytes = bytes;
      this.sampleAtMs = now;
      this.netSamples = [[now, bytes]];
      return;
    }
    const dt = now - this.sampleAtMs;
    if (dt < 1000) return;
    this.sampleBytes = bytes;
    this.sampleAtMs = now;

    // 滚动保留 30 秒。缓冲满时播放器会暂停读取，瞬时吞吐会掉到码率以下，
    // 但那并不代表网络差；只有在整段时间内平均供给跟不上，才是真的供不上。
    this.netSamples.push([now, bytes]);
    const cutoff = now - 30000;
    while (this.netSamples.length > 2 && this.netSamples[0][0] < cutoff) {
      this.netSamples.shift();
    }

    const first = this.netSamples[0];
    const span = now - first[0];
    if (span < 5000) return;
    const mbps = ((bytes - first[1]) * 8) / span / 1000;

    this.netMbps = this.netMbps === 0 ? mbps : this.netMbps * 0.5 + mbps * 0.5;

    if (totalSize > 0 && this.durationMs > 0) {
      this.contentMbps = (totalSize * 8) / (this.durationMs / 1000) / 1000000;
    }
    if (this.contentMbps <= 0) return;

    this.netScore = this.netMbps / this.contentMbps;
    if (this.isPlaying && this.netScore < 0.95) {
      this.lowScoreStreak++;
      if (this.lowScoreStreak >= 3 && !this.netWarningShown) {
        this.netWarningShown = true;
        this.showBriefToast(
          `网络 ${this.netMbps.toFixed(1)} Mbps，此片需 ${this.contentMbps.toFixed(1)} Mbps`
        );
      }
    } else {
      this.lowScoreStreak = 0;
    }
  }

  // ------------------------------------------------------------ 系统级能力

  /** 把播放现场交给 AppStore，UIAbility.onContinue 迁移时直接读这份数据。 */
  private syncLivePlayback(): void {
    if (!this.mediaItem) {
      this.store.setLivePlayback(null);
      return;
    }
    const payload: ContinuePayload = {
      itemId: this.mediaItem.id,
      positionMs: Math.round(this.positionMs),
      audioTrackIndex: this.selectedAudioTrack,
      subtitleTrackIndex: this.subtitle.selectedEmbeddedTrack,
      subtitleDelayMs: this.subtitle.delayMs,
      playbackRate: this.playbackRate
    };
    this.store.setLivePlayback(payload);
  }

  /** 鸿蒙 PC：状态栏常驻项 + 快捷栏「继续观看」任务。非 2in1 设备内部会自动跳过。 */
  private async syncPcSurface(): Promise<void> {
    if (!this.mediaItem || !this.pageActive) return;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!ctx) return;
      const title: string = this.mediaItem.title || '正在播放';
      const detail: string =
        `${Formatters.formatDuration(this.positionMs)} / ${Formatters.formatDuration(this.durationMs)}`;
      if (!this.pcSurfaceShown) {
        await PcSurfaceService.showNowPlaying(ctx, title, detail);
        this.pcSurfaceShown = true;
      } else {
        await PcSurfaceService.updateNowPlayingTitle(ctx, title);
      }
      // 快捷栏任务写盘较贵，且系统会对高频调用报 1010710003，10 秒一次足够
      if (Date.now() - this.lastPcTaskAt > 10000) {
        this.lastPcTaskAt = Date.now();
        await PcSurfaceService.syncContinueTask(ctx, title, detail, this.mediaItem.id, this.positionMs);
      }
    } catch (_e) {
      // PC surfaces are optional; never disturb playback
    }
  }

  private async hidePcSurface(): Promise<void> {
    this.pcSurfaceShown = false;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (ctx) await PcSurfaceService.hideNowPlaying(ctx);
    } catch (_e) {
      // Ignore
    }
  }

  private onPlaybackCompleted(): void {
    this.syncLivePlayback();
    if (this.playNextInPlaylist()) return;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (ctx) ReviewPrompt.onPlaybackFinished(this.store, ctx).catch(() => {});
    } catch (_e) {
      // Ignore
    }
  }

  private playlistIndex(): number {
    if (!this.mediaItem) return -1;
    return this.playlist.findIndex((it: MediaItem) => it.id === this.mediaItem!.id);
  }

  private nextInPlaylist(): MediaItem | null {
    const idx = this.playlistIndex();
    return idx >= 0 && idx < this.playlist.length - 1 ? this.playlist[idx + 1] : null;
  }

  /** 列表播放：播完自动换下一条，复用同一页路由，不叠页面。 */
  private playNextInPlaylist(): boolean {
    const next = this.nextInPlaylist();
    if (!next) return false;
    const src = this.store.sources.find((s) => s.id === next.sourceId);
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/PlayerPage',
      params: {
        item: next,
        source: src,
        startPositionMs: 0,
        playlist: this.playlist
      } as PlayerLaunchParams
    });
    return true;
  }

  private jumpToPlaylist(index: number): void {
    if (index < 0 || index >= this.playlist.length) return;
    const target = this.playlist[index];
    const src = this.store.sources.find((s) => s.id === target.sourceId);
    this.showQueue = false;
    this.getUIContext().getRouter().replaceUrl({
      url: 'pages/PlayerPage',
      params: {
        item: target,
        source: src,
        startPositionMs: 0,
        playlist: this.playlist
      } as PlayerLaunchParams
    });
  }

  private async shareCurrentItem(): Promise<void> {
    if (!this.mediaItem) return;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const thumbnail: string = await this.captureFrameThumbnail(ctx);
    const shared: boolean = await ShareService.shareMediaItem(ctx, this.mediaItem, this.positionMs, thumbnail);
    if (shared) return;
    // 没有可用的分享面板时不能让这次点击落空：链接进剪贴板，用户能粘贴出去。
    const copied: boolean = ShareService.copyShareUrl(this.mediaItem, this.positionMs);
    this.showBriefToast(copied ? '链接已复制，可粘贴分享' : '分享面板不可用');
  }

  /**
   * 分享卡缩略图 = 当前画面帧。
   *
   * 直接读 XComponent 的 surface（官方给视频场景的取帧口径），硬解 / FFmpeg 两条链路都适用，
   * 不受片源是本地还是 WebDAV / SMB 流影响；取不到就返回空串，分享继续但没有缩略图。
   */
  private async captureFrameThumbnail(ctx: common.UIAbilityContext): Promise<string> {
    try {
      const controller: XComponentController =
        this.engineMode === 'native_hw' ? this.nativeController : this.ijkController;
      const surfaceId: string = controller.getXComponentSurfaceId();
      if (!surfaceId) return '';
      const rect: SurfaceRect = controller.getXComponentSurfaceRect();
      let frame: image.PixelMap;
      if (rect.surfaceWidth > 0 && rect.surfaceHeight > 0) {
        const region: image.Region = {
          x: rect.offsetX ?? 0,
          y: rect.offsetY ?? 0,
          size: { width: rect.surfaceWidth, height: rect.surfaceHeight }
        };
        frame = await image.createPixelMapFromSurface(surfaceId, region);
      } else {
        frame = await image.createPixelMapFromSurface(surfaceId);
      }
      return await ShareService.saveFrameThumbnail(ctx, frame);
    } catch (e) {
      hilog.warn(0x0001, 'PrismShare', 'capture frame failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  /** 画中画：系统 VIDEO_PLAY 模板直接复用当前 XComponent 的 Surface。 */
  private async enterPip(): Promise<void> {
    if (this.pipActive) return;
    if (!this.mediaItem) return;
    if (!PiPWindow.isPiPEnabled()) {
      this.showBriefToast('当前设备不支持画中画');
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cfg: PiPWindow.PiPConfiguration = {
        context: ctx,
        componentController: this.engineMode === 'native_hw' ? this.nativeController : this.ijkController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        controlGroups: [PiPWindow.VideoPlayControlGroup.FAST_FORWARD_BACKWARD],
        contentWidth: this.videoWidth,
        contentHeight: this.videoHeight
      };
      const controller: PiPWindow.PiPController = await PiPWindow.create(cfg);
      controller.on('stateChange', (state: PiPWindow.PiPState, _reason: string) => {
        if (state === PiPWindow.PiPState.STARTED) {
          this.pipActive = true;
          this.showControls = false;
        } else if (state === PiPWindow.PiPState.STOPPED) {
          this.pipActive = false;
          this.showControls = true;
        }
      });
      controller.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, _status?: number) => {
        hilog.info(0x0001, 'PrismPip', 'control event=%{public}s', `${event}`);
        if (event === 'playbackStateChanged') {
          this.togglePlayPause();
          if (this.pipController) {
            this.pipController.updatePiPControlStatus(
              PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
              this.isPlaying ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE
            );
          }
        } else if (event === 'fastForward') {
          this.seekTo(this.positionMs + 15000);
        } else if (event === 'fastBackward') {
          this.seekTo(this.positionMs - 15000);
        }
      });
      this.pipController = controller;
      await controller.startPiP();
      this.showBriefToast('已进入画中画');
    } catch (e) {
      hilog.warn(0x0001, 'PrismPip', 'enter pip failed: %{public}s', JSON.stringify(e));
      this.showBriefToast('画中画启动失败');
    }
  }

  private releasePip(): void {
    const controller = this.pipController;
    this.pipController = null;
    if (!controller) return;
    controller.off('stateChange');
    controller.off('controlPanelActionEvent');
    if (this.pipActive) {
      controller.stopPiP().catch(() => {});
    }
    this.pipActive = false;
  }

  private startAVSession(): void {
    if (!this.mediaItem) return;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.avSession.startSession(
      ctx,
      this.mediaItem.id,
      this.mediaItem.title,
      this.mediaItem.qualityTag || 'PrismPlayer',
      this.durationMs,
      {
        onPlay: () => { if (!this.isPlaying) this.togglePlayPause(); },
        onPause: () => { if (this.isPlaying) this.togglePlayPause(); },
        onSeek: (pos: number) => this.seekTo(pos)
      }
    );
  }

  private syncAVSession(): void {
    this.avSession.updatePlaybackState(this.isPlaying, this.positionMs, this.playbackRate);
  }

  private persistProgressNow(finished: boolean = false): void {
    if (!this.mediaItem) return;
    const nearEnd = this.durationMs > 10000 && (this.durationMs - this.positionMs) < 5000;
    // Forward the per-item burn-sub mask memory until a mask UI owns it
    const prev = this.store.getHistoryForItem(this.mediaItem.id);
    this.store.saveWatchProgress({
      itemId: this.mediaItem.id,
      title: this.mediaItem.title,
      subtitleLabel: this.mediaItem.qualityTag,
      posterUrl: this.mediaItem.posterUrl,
      streamUrl: this.mediaItem.streamUrl,
      sourceId: this.mediaItem.sourceId,
      positionMs: Math.round(this.positionMs),
      durationMs: Math.round(this.durationMs),
      audioTrackIndex: this.selectedAudioTrack,
      subtitleTrackIndex: this.subtitle.selectedEmbeddedTrack,
      subtitleDelayMs: this.subtitle.delayMs,
      playbackRate: this.playbackRate,
      // Once the mask UI owns this item (user toggled / adjusted / detected), page state wins; otherwise forward the stored value
      maskEnabled: this.subtitle.maskConfigured ? (this.subtitle.maskEnabled ? 1 : 0) : (prev ? prev.maskEnabled : -1),
      maskYTop: this.subtitle.maskConfigured ? this.subtitle.maskYTop : (prev ? prev.maskYTop : -1),
      maskYBottom: this.subtitle.maskConfigured ? this.subtitle.maskYBottom : (prev ? prev.maskYBottom : -1),
      updatedAt: Date.now(),
      finished: finished || nearEnd
    });
    this.syncPcSurface();
  }

  private isLocalPlayback(): boolean {
    return !!this.mediaItem && BurnSubDetector.isLocalPlayable(this.mediaItem.streamUrl);
  }

  private maskPictureRect(): PictureRect {
    return computePictureRect(this.viewportWidthVp, this.viewportHeightVp, this.getSurfaceAspect());
  }

  /** Keep subtitles inside the picture bottom, lifting only when the control panel overlaps it. */
  private subtitleBottomInset(): number {
    const rect = this.maskPictureRect();
    const margin = 16;
    if (!this.showControls) return margin;
    const controlsTop = this.viewportHeightVp - 130;
    const pictureBottom = rect.topVp + rect.heightVp;
    return pictureBottom > controlsTop ? Math.ceil(pictureBottom - controlsTop + margin) : margin;
  }

  private startMaskAdjust(): void {
    this.subtitlePage = 'none';
    this.subtitle.setMaskEnabled(true);
    this.showControls = false;
    this.maskAdjusting = true;
  }

  private finishMaskAdjust(): void {
    this.maskAdjusting = false;
    this.showControls = true;
    this.scheduleHideControls();
    this.subtitle.commitMask();
    this.showBriefToast('遮挡范围已保存');
  }

  private onMaskDrag(yTop: number, yBottom: number): void {
    this.subtitle.setMaskRange(yTop, yBottom);
  }

  private handleKeyEvent(event: KeyEvent): void {
    if (event.type !== KeyType.Down) return;
    if (this.subtitlePage !== 'none') {
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE || event.keyCode === KeyCode.KEYCODE_S) {
        this.closeSubtitleFlow();
      }
      return;
    }
    this.wakeControls();
    const hasShift = event.getModifierKeyState ? event.getModifierKeyState(['Shift']) : false;

    switch (event.keyCode) {
      case KeyCode.KEYCODE_SPACE:
        this.togglePlayPause();
        break;
      case KeyCode.KEYCODE_DPAD_LEFT:
        this.seekTo(this.positionMs - (hasShift ? 30000 : 5000));
        this.showBriefToast(hasShift ? '快退 30 秒' : '快退 5 秒');
        break;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        this.seekTo(this.positionMs + (hasShift ? 30000 : 5000));
        this.showBriefToast(hasShift ? '快进 30 秒' : '快进 5 秒');
        break;
      case KeyCode.KEYCODE_DPAD_UP:
        this.applyVolume(this.volume + 0.05);
        this.showBriefToast(`音量 ${Math.round(this.volume * 100)}%`);
        break;
      case KeyCode.KEYCODE_DPAD_DOWN:
        this.applyVolume(this.volume - 0.05);
        this.showBriefToast(`音量 ${Math.round(this.volume * 100)}%`);
        break;
      case KeyCode.KEYCODE_F:
        this.toggleFullscreen();
        break;
      case KeyCode.KEYCODE_ESCAPE:
        if (this.maskAdjusting) this.finishMaskAdjust();
        else if (this.drawerTab !== 'none') this.drawerTab = 'none';
        else if (this.isFullscreen) this.toggleFullscreen();
        else this.getUIContext().getRouter().back();
        break;
      case KeyCode.KEYCODE_LEFT_BRACKET: {
        const rates = AppConstants.PLAYBACK_RATES;
        const idx = rates.indexOf(this.playbackRate);
        if (idx > 0) this.setRate(rates[idx - 1]);
        else this.setRate(Math.max(0.5, this.playbackRate - 0.25));
        break;
      }
      case KeyCode.KEYCODE_RIGHT_BRACKET: {
        const rates = AppConstants.PLAYBACK_RATES;
        const idx = rates.indexOf(this.playbackRate);
        if (idx >= 0 && idx < rates.length - 1) this.setRate(rates[idx + 1]);
        else this.setRate(Math.min(3.0, this.playbackRate + 0.25));
        break;
      }
      case KeyCode.KEYCODE_S:
        this.toggleSubtitleCenter();
        break;
      case KeyCode.KEYCODE_A:
        this.refreshNativeTracks();
        this.refreshIjkAudioStreams();
        this.drawerTab = this.drawerTab === 'settings' ? 'none' : 'settings';
        break;
      case KeyCode.KEYCODE_I:
        this.showStatsOsd = !this.showStatsOsd;
        break;
      case KeyCode.KEYCODE_M:
        this.muted = !this.muted;
        this.applyVolume(this.volume);
        this.showBriefToast(this.muted ? '已静音' : '已取消静音');
        break;
      default:
        break;
    }
  }

  private openSubtitleCenter(): void {
    this.drawerTab = 'none';
    this.refreshNativeTracks();
    this.subtitle.setEmbeddedTracks(this.tracks.filter(t => t.kind === 'subtitle'), this.engineMode === 'native_hw');
    this.subtitlePage = 'hub';
    this.showControls = false;
  }

  private closeSubtitleFlow(): void {
    this.subtitlePage = 'none';
    this.showControls = true;
    this.scheduleHideControls();
  }

  private toggleSubtitleCenter(): void {
    if (this.subtitlePage !== 'none') {
      this.closeSubtitleFlow();
    } else {
      this.openSubtitleCenter();
    }
  }

  onBackPress(): boolean {
    if (this.maskAdjusting) {
      this.finishMaskAdjust();
      return true;
    }
    if (this.subtitlePage !== 'none') {
      this.closeSubtitleFlow();
      return true;
    }
    if (this.drawerTab !== 'none') {
      this.drawerTab = 'none';
      return true;
    }
    return false;
  }

  private getSurfaceWidth(): string {
    if (this.aspectMode === 'fill') return '100%';
    return '100%';
  }

  private getSurfaceAspect(): number | undefined {
    if (this.aspectMode === '16:9') return 16 / 9;
    if (this.aspectMode === '21:9') return 21 / 9;
    if (this.aspectMode === '4:3') return 4 / 3;
    if (this.aspectMode === 'fit' && this.videoWidth > 0 && this.videoHeight > 0) {
      return this.videoWidth / this.videoHeight;
    }
    return undefined;
  }

  @Builder
  skipRow(kind: string) {
    Row() {
      Text(kind === 'intro' ? '片头' : '片尾').fontSize(13).fontColor(Color.White)
      Blank()
      Row() {
        Text('−').fontSize(16).fontColor(Color.White)
      }
      .width(32)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#1B1E27')
      .borderRadius(8)
      .onClick(() => {
        if (kind === 'intro') {
          this.applySkip(Math.max(0, this.skipIntroSec - 15), this.skipOutroSec);
        } else {
          this.applySkip(this.skipIntroSec, Math.max(0, this.skipOutroSec - 15));
        }
      })
      Text(kind === 'intro'
        ? (this.skipIntroSec > 0 ? `${this.skipIntroSec}s` : '关闭')
        : (this.skipOutroSec > 0 ? `${this.skipOutroSec}s` : '关闭'))
        .fontSize(13)
        .fontColor((kind === 'intro' ? this.skipIntroSec : this.skipOutroSec) > 0 ? '#F3F4F6' : '#6B7280')
        .width(56)
        .textAlign(TextAlign.Center)
      Row() {
        Text('+').fontSize(16).fontColor(Color.White)
      }
      .width(32)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#1B1E27')
      .borderRadius(8)
      .onClick(() => {
        if (kind === 'intro') {
          this.applySkip(Math.min(600, this.skipIntroSec + 15), this.skipOutroSec);
        } else {
          this.applySkip(this.skipIntroSec, Math.min(600, this.skipOutroSec + 15));
        }
      })
    }
    .width('100%')
    .height(40)
  }

  @Builder
  drawerChip(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .layoutWeight(1)
      .height(36)
      .fontSize(12)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(active ? Color.White : '#9CA3AF')
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .padding({ left: 4, right: 4 })
      .borderRadius(8)
      .backgroundColor(active ? '#3B82F6' : '#14161D')
      .border({ width: 0.7, color: active ? '#3B82F6' : '#1FFFFFFF' })
      .onClick(() => onTap())
  }

  /** 宽窗（平板横屏 / 2in1）把底部抽屉改成居中面板，避免横跨 1500vp 的抽屉。 */
  private wideSheet(): boolean {
    return this.viewportWidthVp >= 1000;
  }

  private modalSheetVisible(): boolean {
    return this.subtitlePage !== 'none' || this.drawerTab === 'settings';
  }

  private modalSheetHeight(): string {
    if (this.subtitlePage === 'hub') return '82%';
    if (this.subtitlePage !== 'none') return '92%';
    return '58%';
  }

  @Builder
  unifiedSheetBuilder() {
    if (this.drawerTab === 'settings') {
      this.playbackSheetBuilder()
    } else {
      this.subtitleSheetBuilder()
    }
  }

  @Builder
  playbackSheetBuilder() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('播放设置')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(13)
            .fontColor(['#9CA3AF'])
        }
        .width(30)
        .height(30)
        .backgroundColor('#1B1E27')
        .onClick(() => { this.drawerTab = 'none'; })
      }
      .width('100%')

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text('画面比例').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#9CA3AF')
            Row({ space: 6 }) {
              ForEach(['fit', 'fill', '16:9', '21:9', '4:3'] as AspectMode[], (m: AspectMode) => {
                this.drawerChip(
                  m === 'fit' ? '适应' : (m === 'fill' ? '铺满' : m),
                  this.aspectMode === m,
                  () => { this.aspectMode = m; }
                )
              }, (m: AspectMode) => `${m}_${this.aspectMode === m}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('播放倍速').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#9CA3AF')
            Row({ space: 6 }) {
              ForEach(AppConstants.PLAYBACK_RATES.slice(0, 4), (r: number) => {
                this.drawerChip(`${r}x`, this.playbackRate === r, () => this.setRate(r))
              }, (r: number) => `${r}_${this.playbackRate === r}`)
            }.width('100%')
            Row({ space: 6 }) {
              ForEach(AppConstants.PLAYBACK_RATES.slice(4), (r: number) => {
                this.drawerChip(`${r}x`, this.playbackRate === r, () => this.setRate(r))
              }, (r: number) => `${r}_${this.playbackRate === r}`)
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('跳过片头 / 片尾').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#9CA3AF')
            this.skipRow('intro')
            this.skipRow('outro')
          }.width('100%').alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('解码内核').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#9CA3AF')
            Row({ space: 6 }) {
              this.drawerChip('硬解', this.engineMode === 'native_hw', () => this.switchEngine('native_hw'))
              this.drawerChip('FFmpeg', this.engineMode === 'ffmpeg_sw', () => this.switchEngine('ffmpeg_sw'))
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          if (this.hasAudioChoices()) {
            Column({ space: 8 }) {
              Text('音轨选择').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#9CA3AF')
              if (this.engineMode === 'native_hw') {
                ForEach(this.tracks.filter(t => t.kind === 'audio'), (trk: PlayerTrackItem) => {
                  Row() {
                    Column({ space: 2 }) {
                      Text(trk.label).fontSize(13).fontColor(Color.White)
                      if (trk.details || trk.codec) {
                        Text(`${trk.codec} ${trk.details}`).fontSize(11).fontColor('#6B7280')
                      }
                    }.alignItems(HorizontalAlign.Start)
                    Blank()
                    if (this.selectedAudioTrack === trk.index) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                        .fontSize(16)
                        .fontColor(['#3B82F6'])
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(10)
                  .backgroundColor('#14161D')
                  .onClick(() => {
                    if (this.nativePlayerId > 0) {
                      prismNative.selectPlayerTrack(this.nativePlayerId, trk.index);
                      this.selectedAudioTrack = trk.index;
                      this.showBriefToast(`已切换音轨：${trk.label}`);
                    }
                  })
                }, (trk: PlayerTrackItem) => `${trk.index}_${this.selectedAudioTrack === trk.index}`)
              } else {
                ForEach(this.ijkAudioStreams, (st: IjkAudioStream) => {
                  Row() {
                    Column({ space: 2 }) {
                      Text(st.label).fontSize(13).fontColor(Color.White)
                      Text(`流序号 ${st.streamIndex} · ${st.codec}`)
                        .fontSize(11)
                        .fontColor('#6B7280')
                    }.alignItems(HorizontalAlign.Start)
                    Blank()
                    if (this.selectedIjkAudioStream === st.streamIndex) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                        .fontSize(16)
                        .fontColor(['#3B82F6'])
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(10)
                  .backgroundColor('#14161D')
                  .onClick(() => this.selectIjkAudioStream(st.streamIndex))
                }, (st: IjkAudioStream) => `ijk_${st.streamIndex}_${this.selectedIjkAudioStream === st.streamIndex}`)
              }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
      }.edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 12, bottom: 24 })
    .backgroundColor('#FF12151E')
  }

  @Builder
  subtitleSheetBuilder() {
    Column() {
      if (this.subtitlePage === 'hub') {
        SubtitleHubPage({
          onNavigate: (route: SubtitlePageRoute) => { this.subtitlePage = route; },
          onClose: () => this.closeSubtitleFlow()
        })
      } else if (this.subtitlePage === 'tracks') {
        SubtitleTracksPage({
          onBack: () => { this.subtitlePage = 'hub'; },
          onClose: () => this.closeSubtitleFlow()
        })
      } else if (this.subtitlePage === 'style') {
        SubtitleStylePage({
          onBack: () => { this.subtitlePage = 'hub'; },
          onClose: () => this.closeSubtitleFlow()
        })
      } else if (this.subtitlePage === 'sync') {
        SubtitleSyncPage({
          onBack: () => { this.subtitlePage = 'hub'; },
          onClose: () => this.closeSubtitleFlow()
        })
      } else if (this.subtitlePage === 'online') {
        SubtitleOnlinePage({
          onBack: () => { this.subtitlePage = 'hub'; },
          onClose: () => this.closeSubtitleFlow()
        })
      } else if (this.subtitlePage === 'assist') {
        SubtitleAssistPage({
          onBack: () => { this.subtitlePage = 'hub'; },
          onClose: () => this.closeSubtitleFlow()
        })
      } else if (this.subtitlePage === 'mask') {
        SubtitleMaskPage({
          onBack: () => { this.subtitlePage = 'hub'; },
          onClose: () => this.closeSubtitleFlow(),
          onManualAdjust: () => this.startMaskAdjust()
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF0B0D12')
  }

  build() {
    Stack() {
      // Video Render Surface (Dual Engine)
      Column() {
        if (this.engineMode === 'native_hw') {
          XComponent({
            id: 'prism_video_surface',
            type: XComponentType.SURFACE,
            libraryname: 'prismplayer',
            controller: this.nativeController
          })
            .width(this.getSurfaceWidth())
            .aspectRatio(this.getSurfaceAspect())
            .constraintSize({ maxWidth: '100%', maxHeight: '100%' })
            .onLoad(() => {
              this.nativeSurfaceReady = true;
              this.startNativeEngine();
            })
        } else {
          XComponent({
            id: 'ijk_video_surface',
            type: XComponentType.SURFACE,
            libraryname: 'ijkplayer_napi',
            controller: this.ijkController
          })
            .width(this.getSurfaceWidth())
            .aspectRatio(this.getSurfaceAspect())
            .constraintSize({ maxWidth: '100%', maxHeight: '100%' })
            .onLoad((ctx?: object) => {
              if (ctx) {
                this.ijkContext = ctx;
                this.startIjkEngine();
              }
            })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#000000')

      // Burned-in Subtitle Occlusion Band (English-learning mask, above the video picture, below all overlays)
      if (this.subtitle.maskEnabled) {
        SubtitleMaskBand({
          peeking: this.maskPeeking,
          adjusting: this.maskAdjusting,
          yTop: this.subtitle.maskYTop,
          yBottom: this.subtitle.maskYBottom,
          picture: this.maskPictureRect(),
          onChange: (yTop: number, yBottom: number): void => {
            this.onMaskDrag(yTop, yBottom);
          }
        })
      }

      // Brightness Dimmer Layer (non-blocking visual dimming across phone / tablet / PC / emulator)
      if (this.screenBrightness < 0.99) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .opacity(Math.max(0, Math.min(0.75, 1 - this.screenBrightness)))
          .hitTestBehavior(HitTestMode.None)
      }

      // ASS / SRT / VTT Synchronized Subtitle Overlay
      if (this.subtitle.enabled && !this.pipActive) {
        SubtitleOverlay({
          cues: this.activeCues,
          bottomInsetVp: this.subtitleBottomInset(),
          picture: this.maskPictureRect()
        })
      }

      // Touch & Mouse Gesture Layer (suppressed while adjusting the mask band so band drags win)
      if (!this.maskAdjusting) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((ev: TouchEvent) => {
          if (ev.type === TouchType.Down && ev.touches.length > 0) {
            this.lastTouchX = ev.touches[0].x;
          }
        })
        .onMouse(() => {
          this.wakeControls();
        })
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 }).onAction(() => {
              if (this.screenLocked) return;
              this.togglePlayPause();
            }),
            LongPressGesture({ duration: 350, repeat: false })
              .onAction(() => {
                if (this.subtitle.maskEnabled && !this.maskAdjusting && !this.screenLocked) {
                  this.maskPeeking = true;
                }
              })
              .onActionEnd(() => {
                this.maskPeeking = false;
              })
              .onActionCancel(() => {
                this.maskPeeking = false;
              }),
            TapGesture({ count: 1 }).onAction(() => {
              if (this.drawerTab !== 'none') {
                // Drawer button taps pass through the transparent controls layer;
                // keep controls alive here and let the drawer scrim handle outside taps
                this.wakeControls();
                return;
              }
              this.showControls = !this.showControls;
              if (this.showControls) this.scheduleHideControls();
            }),
            PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
              .onActionStart(() => {
                if (this.screenLocked) return;
                this.panZone = 'seek';
                this.gestureStartPosMs = this.positionMs;
                this.isSeekingSlider = true;
              })
              .onActionUpdate((ev: GestureEvent) => {
                if (this.screenLocked || this.panZone !== 'seek') return;
                const safeDur = this.durationMs > 0 ? this.durationMs : 600000;
                const fullSwipeSpanMs = Math.min(180000, Math.max(60000, safeDur * 0.4));
                const deltaMs = (ev.offsetX / Math.max(240, this.viewportWidthVp)) * fullSwipeSpanMs;
                const preview = Math.max(0, Math.min(safeDur, this.gestureStartPosMs + deltaMs));
                const diffSec = Math.round((preview - this.gestureStartPosMs) / 1000);
                this.positionMs = preview;
                this.gestureKind = 'seek';
                this.gestureLabel = `${Formatters.formatDuration(preview)} / ${Formatters.formatDuration(this.durationMs)}`;
                this.gestureSubLabel = diffSec >= 0 ? `快进 +${diffSec}s` : `快退 ${diffSec}s`;
                this.gestureRatio = safeDur > 0 ? Math.max(0, Math.min(1, preview / safeDur)) : 0;
              })
              .onActionEnd(() => {
                if (this.panZone === 'seek') {
                  this.isSeekingSlider = false;
                  this.seekTo(this.positionMs);
                }
                this.panZone = 'none';
                this.gestureKind = 'none';
              }),
            PanGesture({ direction: PanDirection.Vertical, distance: 12 })
              .onActionStart((ev: GestureEvent) => {
                if (this.screenLocked) return;
                const fallbackMid = (this.viewportWidthVp > 0 ? this.viewportWidthVp : 360) * 0.5;
                let x = fallbackMid;
                if (this.lastTouchX >= 0) {
                  x = this.lastTouchX;
                } else if (ev.fingerList.length > 0) {
                  x = ev.fingerList[0].localX;
                }
                this.panZone = x < fallbackMid ? 'bright' : 'vol';
                this.gestureStartBright = this.screenBrightness;
                this.gestureStartVol = this.volume;
              })
              .onActionUpdate((ev: GestureEvent) => {
                if (this.screenLocked) return;
                const spanY = Math.max(180, this.viewportHeightVp * 0.55);
                const delta = -ev.offsetY / spanY;
                if (this.panZone === 'bright') {
                  this.applyBrightness(this.gestureStartBright + delta);
                  this.gestureKind = 'bright';
                  this.gestureLabel = `亮度 ${Math.round(this.screenBrightness * 100)}%`;
                  this.gestureSubLabel = '左侧上下滑动调节明暗度';
                  this.gestureRatio = this.screenBrightness;
                } else if (this.panZone === 'vol') {
                  this.applyVolume(this.gestureStartVol + delta);
                  this.gestureKind = 'vol';
                  this.gestureLabel = `音量 ${Math.round(this.volume * 100)}%`;
                  this.gestureSubLabel = '右侧上下滑动调节音量';
                  this.gestureRatio = this.volume;
                }
              })
              .onActionEnd(() => {
                this.panZone = 'none';
                this.gestureKind = 'none';
              })
          )
        )
      }

      // Buffering Spinner
      if (this.isBuffering) {
        Column({ space: 8 }) {
          LoadingProgress().width(42).height(42).color('#3B82F6')
          Text('正在缓冲高清流...')
            .fontSize(12)
            .fontColor(Color.White)
        }
        .padding(16)
        .borderRadius(12)
        .backgroundColor('#990A0B0F')
        .hitTestBehavior(HitTestMode.None)
      }

      // Friendly Playback Error Card
      if (this.errorBanner) {
        Column({ space: 14 }) {
          Row({ space: 10 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle_fill'))
                .fontSize(20)
                .fontColor(['#F59E0B'])
            }
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor('#24FBBF24')
            .justifyContent(FlexAlign.Center)

            Text('暂时无法播放此影片')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F3F4F6')
          }.width('100%')

          Text(this.errorBanner)
            .fontSize(13)
            .lineHeight(20)
            .fontColor('#9CA3AF')
            .width('100%')

          Row({ space: 10 }) {
            Button(this.engineMode === 'native_hw' ? '切换兼容模式' : '再试一次')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor('#3B82F6')
              .borderRadius(10)
              .onClick(() => {
                if (this.engineMode === 'native_hw') {
                  this.switchEngine('ffmpeg_sw');
                } else {
                  this.startIjkEngine();
                }
              })
            Button('返回')
              .type(ButtonType.Normal)
              .width(104)
              .height(40)
              .fontSize(14)
              .fontColor('#E5E7EB')
              .backgroundColor('#1B1E27')
              .borderRadius(10)
              .border({ width: 0.7, color: '#26FFFFFF' })
              .onClick(() => this.getUIContext().getRouter().back())
          }.width('100%')
        }
        .width('86%')
        .constraintSize({ maxWidth: 380 })
        .padding(20)
        .borderRadius(18)
        .backgroundColor('#F2141824')
        .border({ width: 0.9, color: '#33FFFFFF' })
        .shadow({ radius: 28, color: '#CC000000', offsetX: 0, offsetY: 10 })
      }

      // Interactive Center Gesture Feedback HUD (Brightness / Volume / Seek)
      if (this.gestureKind !== 'none') {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph(
              this.gestureKind === 'bright'
                ? $r('sys.symbol.sun_max_fill')
                : (this.gestureKind === 'vol'
                  ? (this.volume <= 0.01 ? $r('sys.symbol.speaker_slash_fill') : $r('sys.symbol.speaker_wave_2_fill'))
                  : $r('sys.symbol.forward_end_fill'))
            )
              .fontSize(20)
              .fontColor([this.gestureKind === 'bright' ? '#D97706' : '#3B82F6'])

            Text(this.gestureLabel)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }

          Row() {
            Row()
              .width(`${Math.round(Math.max(0, Math.min(1, this.gestureRatio)) * 100)}%`)
              .height(4)
              .backgroundColor(this.gestureKind === 'bright' ? '#D97706' : '#3B82F6')
              .borderRadius(2)
          }
          .width(176)
          .height(4)
          .backgroundColor('#38FFFFFF')
          .borderRadius(2)

          Text(this.gestureSubLabel)
            .fontSize(11)
            .fontColor('#9CA3AF')
        }
        .padding({ left: 18, right: 18, top: 12, bottom: 12 })
        .borderRadius(14)
        .backgroundColor('#CC0E1119')
        .border({ width: 0.8, color: '#33FFFFFF' })
        .hitTestBehavior(HitTestMode.None)
      }

      // Transient Toast / Gesture Preview
      if (this.toastText && this.gestureKind === 'none') {
        Text(this.toastText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .backgroundColor('#B3000000')
          .position({ x: '50%', y: '18%' })
          .translate({ x: '-50%' })
          .hitTestBehavior(HitTestMode.None)
      }

      // Technical Stats OSD (Press 'I' on PC or toggle in Settings drawer)
      if (this.showStatsOsd) {
        Column({ space: 4 }) {
          Text(`内核引擎：${this.engineMode === 'native_hw' ? 'OH_AVPlayer 硬件解码' : 'FFmpeg 软解 (@ohos/ijkplayer)'}`)
            .fontSize(11).fontColor('#94A3B8')
          if (this.decodeRouteReason) {
            Text(`路由决策：${this.decodeRouteReason}`)
              .fontSize(10).fontColor('#D97706').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.activeCodecMime) {
            Text(`解码器：${CodecCapability.decoderName(this.activeCodecMime) || this.activeCodecMime}（${this.activeCodecMime}）`)
              .fontSize(10).fontColor('#94A3B8').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(`分辨率：${this.videoWidth} × ${this.videoHeight} · 倍速：${this.playbackRate}x`)
            .fontSize(11).fontColor(Color.White)
          Text(`C++ Range Proxy：127.0.0.1:${this.store.proxyPort} · 已吞吐 ${this.proxyBytesText}`)
            .fontSize(11).fontColor(Color.White)
          Text(`块缓存命中率：${this.proxyHitRate}`)
            .fontSize(11).fontColor('#10B981')
          if (this.proxyResolvedUrl) {
            Text(`直链：${this.proxyResolvedUrl}`)
              .fontSize(10).fontColor('#6B7280').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.contentMbps > 0) {
            Text(`网络 ${this.netMbps.toFixed(1)} Mbps ／ 码率 ${this.contentMbps.toFixed(1)} Mbps ／ 评分 ${(this.netScore * 100).toFixed(0)}%`)
              .fontSize(11)
              .fontColor(this.netScore >= 1.5 ? '#10B981' : (this.netScore >= 0.95 ? '#F59E0B' : '#EF4444'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width(340)
        .padding(12)
        .borderRadius(12)
        .backgroundColor('#E60A0B0F')
        .border({ width: 0.8, color: '#26FFFFFF' })
        .alignItems(HorizontalAlign.Start)
        .position({ left: 18, top: 108 })
      }

      // Player Controls Overlay（画中画期间由系统面板接管，主窗口不再绘制）
      if (this.showControls && !this.pipActive && !this.showQueue) {
        Column() {
          // Top Bar
          Row({ space: 10 }) {
            if (!this.screenLocked) {
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_chevron_left'))
                  .width(16)
                  .height(16)
                  .fillColor(Color.White)
              }
              .width(38)
              .height(38)
              .backgroundColor('#80141720')
              .border({ width: 0.6, color: '#33FFFFFF' })
              .onClick(() => this.getUIContext().getRouter().back())

              Column({ space: 2 }) {
                Text(this.mediaItem ? this.mediaItem.title : '正在播放')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.mediaItem && this.mediaItem.qualityTag) {
                  Text(`${this.mediaItem.qualityTag} · ${this.engineMode === 'native_hw' ? '硬解' : 'FFmpeg'}` +
                    (this.playlistIndex() >= 0 && this.playlist.length > 1
                      ? ` · ${this.playlistIndex() + 1}/${this.playlist.length}`
                      : ''))
                    .fontSize(11)
                    .fontColor('#94A3B8')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .onClick(() => {
                      if (this.playlist.length > 1) this.showQueue = true;
                    })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Button({ type: ButtonType.Circle }) {
                SymbolGlyph(this.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(15)
                  .fontColor([this.isFavorite ? '#EF4444' : Color.White])
              }
              .width(36)
              .height(36)
              .backgroundColor('#80141720')
              .border({ width: 0.6, color: this.isFavorite ? '#66EF4444' : '#33FFFFFF' })
              .onClick(async () => {
                if (this.mediaItem) {
                  this.isFavorite = await this.store.toggleFavorite(this.mediaItem.id);
                  this.showBriefToast(this.isFavorite ? '已加入收藏' : '已取消收藏');
                }
              })

              Button({ type: ButtonType.Circle }) {
                SymbolGlyph(this.screenLocked ? $r('sys.symbol.lock_fill') : $r('sys.symbol.lock_open_fill'))
                  .fontSize(15)
                  .fontColor([this.screenLocked ? '#D97706' : Color.White])
              }
              .width(36)
              .height(36)
              .backgroundColor('#80141720')
              .border({ width: 0.6, color: '#33FFFFFF' })
              .onClick(() => {
                this.screenLocked = !this.screenLocked;
                this.showBriefToast(this.screenLocked ? '已锁定触摸手势' : '已解锁');
              })

              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                  .fontSize(17)
                  .fontColor([Color.White])
              }
              .width(36)
              .height(36)
              .backgroundColor('#80141720')
              .border({ width: 0.6, color: '#33FFFFFF' })
              .bindMenu([
                {
                  value: '画中画播放',
                  action: () => { this.enterPip(); }
                },
                {
                  value: this.playlist.length > 1
                    ? `播放队列 (${this.playlistIndex() + 1}/${this.playlist.length})`
                    : '播放队列',
                  action: () => { this.showQueue = this.playlist.length > 1; }
                },
                {
                  value: '分享这部片',
                  action: () => { this.shareCurrentItem(); }
                },
                {
                  value: this.engineMode === 'native_hw' ? '切换至 FFmpeg 兼容解码' : '切换至系统硬解内核',
                  action: () => { this.switchEngine(this.engineMode === 'native_hw' ? 'ffmpeg_sw' : 'native_hw'); }
                },
                {
                  value: this.showStatsOsd ? '隐藏技术参数面板' : '显示技术参数面板',
                  action: () => { this.showStatsOsd = !this.showStatsOsd; }
                },
                {
                  value: this.isFullscreen ? '退出全屏' : '切换全屏',
                  action: () => { this.toggleFullscreen(); }
                }
              ], playerMenuOptions())
            } else {
              Blank()
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.lock_fill'))
                  .fontSize(15)
                  .fontColor(['#D97706'])
              }
              .width(36)
              .height(36)
              .backgroundColor('#80141720')
              .border({ width: 0.6, color: '#33FFFFFF' })
              .onClick(() => {
                this.screenLocked = false;
                this.showBriefToast('已解锁');
              })
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 16, bottom: 16 })
          .linearGradient({ angle: 180, colors: [['#CC000000', 0], ['#00000000', 1]] })

          Blank()

          // Bottom Floating Frosted Control Capsule
          if (!this.screenLocked) {
            Column({ space: 10 }) {
              if (this.showOutroSkip()) {
                Row() {
                  Blank()
                  Button('跳过片尾')
                    .height(32)
                    .fontSize(12)
                    .fontColor(Color.White)
                    .backgroundColor('#66191D2A')
                    .borderRadius(16)
                    .border({ width: 0.6, color: '#33FFFFFF' })
                    .onClick(() => this.seekTo(Math.max(0, this.durationMs - 400)))
                }
                .width('100%')
              }

              if (this.nextInPlaylist() !== null) {
                Row() {
                  Blank()
                  Row() {
                    Text(`下一部 · ${this.nextInPlaylist()!.title}`)
                      .fontSize(11)
                      .fontColor(Color.White)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .borderRadius(15)
                  .backgroundColor('#66191D2A')
                  .border({ width: 0.6, color: '#33FFFFFF' })
                  .constraintSize({ maxWidth: '68%' })
                  .onClick(() => { this.playNextInPlaylist(); })
                }
                .width('100%')
              }

              Row({ space: 10 }) {
                Text(Formatters.formatDuration(this.positionMs))
                  .fontSize(12)
                  .fontColor(Color.White)
                  .width(54)

                Slider({
                  value: this.positionMs,
                  min: 0,
                  max: this.durationMs > 0 ? this.durationMs : 1000,
                  step: 500
                })
                  .layoutWeight(1)
                  .selectedColor('#3B82F6')
                  .trackColor('#4DFFFFFF')
                  .blockColor(Color.White)
                  .onChange((val: number, mode: SliderChangeMode) => {
                    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                      this.isSeekingSlider = true;
                      this.positionMs = val;
                      this.wakeControls();
                    } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                      this.isSeekingSlider = false;
                      this.seekTo(val);
                    }
                  })

                Text(Formatters.formatDuration(this.durationMs))
                  .fontSize(12)
                  .fontColor('#9CA3AF')
                  .width(54)
                  .textAlign(TextAlign.End)
              }
              .width('100%')

              Row({ space: 10 }) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.gobackward_15'))
                    .fontSize(16)
                    .fontColor([Color.White])
                }
                .width(38)
                .height(38)
                .backgroundColor('#66191D2A')
                .onClick(() => this.seekTo(this.positionMs - 15000))

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
                    .fontSize(18)
                    .fontColor([Color.White])
                }
                .width(44)
                .height(44)
                .backgroundColor('#3B82F6')
                .shadow({ radius: 10, color: '#665E8BFF', offsetX: 0, offsetY: 2 })
                .onClick(() => this.togglePlayPause())

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.goforward_15'))
                    .fontSize(16)
                    .fontColor([Color.White])
                }
                .width(38)
                .height(38)
                .backgroundColor('#66191D2A')
                .onClick(() => this.seekTo(this.positionMs + 15000))

                Blank()

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.textformat_size_square_fill'))
                    .fontSize(17)
                    .fontColor([this.subtitlePage !== 'none' ? '#3B82F6' : Color.White])
                }
                .width(38)
                .height(38)
                .backgroundColor('#66191D2A')
                .onClick(() => this.toggleSubtitleCenter())

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
                    .fontSize(17)
                    .fontColor([this.drawerTab === 'settings' ? '#3B82F6' : Color.White])
                }
                .width(38)
                .height(38)
                .backgroundColor('#66191D2A')
                .onClick(() => {
                  this.refreshNativeTracks();
                  this.refreshIjkAudioStreams();
                  this.drawerTab = this.drawerTab === 'settings' ? 'none' : 'settings';
                })

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph(
                    this.isFullscreen
                      ? $r('sys.symbol.arrow_down_right_and_arrow_up_left')
                      : $r('sys.symbol.arrow_up_left_and_arrow_down_right')
                  )
                    .fontSize(16)
                    .fontColor([this.isFullscreen ? '#94A3B8' : Color.White])
                }
                .width(38)
                .height(38)
                .backgroundColor('#66191D2A')
                .onClick(() => this.toggleFullscreen())
              }
              .width('100%')
            }
            .width(this.viewportWidthVp >= 1200 ? 880 : (this.viewportWidthVp > 760 ? 760 : '94%'))
            .padding(this.viewportHeightVp < 500 ? 10 : 14)
            .margin({
              bottom: this.viewportHeightVp < 500 ? 10 : 18
            })
            .borderRadius(18)
            .backgroundColor('#CC10131C')
            .backdropBlur(20)
            .border({ width: 0.8, color: '#26FFFFFF' })
          }
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 播放队列：电影列表播放的完整列表，点任意一条跳播
      if (this.showQueue && this.playlist.length > 1) {
        Column() {
          Column({ space: 10 }) {
            Row() {
              Text(`播放队列 · ${this.playlist.length} 部`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F3F4F6')
              Blank()
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor(['#C7CBD3'])
              }
              .width(30)
              .height(30)
              .backgroundColor('#1B1E27')
              .onClick(() => { this.showQueue = false; })
            }
            .width('100%')

            List({ space: 4 }) {
              ForEach(this.playlist, (it: MediaItem, idx: number) => {
                ListItem() {
                  Row({ space: 10 }) {
                    Text(`${idx + 1}`)
                      .fontSize(12)
                      .fontColor(idx === this.playlistIndex() ? '#60A5FA' : '#6B7280')
                      .width(22)
                    Column({ space: 2 }) {
                      Text(it.title)
                        .fontSize(13)
                        .fontColor('#F3F4F6')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(Formatters.formatDuration(it.durationMs))
                        .fontSize(10)
                        .fontColor('#6B7280')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    if (idx === this.playlistIndex()) {
                      SymbolGlyph($r('sys.symbol.play_fill')).fontSize(13).fontColor(['#60A5FA'])
                    }
                  }
                  .width('100%')
                  .height(52)
                  .padding({ left: 8, right: 10 })
                  .borderRadius(10)
                  .backgroundColor(idx === this.playlistIndex() ? '#1A3B82F6' : Color.Transparent)
                  .onClick(() => this.jumpToPlaylist(idx))
                }
              }, (it: MediaItem) => it.id)
            }
            .width('100%')
            .height(Math.min(this.playlist.length * 56, 320))
            .scrollBar(BarState.Off)
          }
          .width('86%')
          .constraintSize({ maxWidth: 380 })
          .padding(16)
          .borderRadius(18)
          .backgroundColor('#F210131C')
          .border({ width: 0.8, color: '#26FFFFFF' })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#B3000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.showQueue = false; })
      }

      // Floating done chip while adjusting the burned-subtitle mask band
      if (this.maskAdjusting) {
        Row({ space: 12 }) {
          Text('拖动黑条上下边缘调整遮挡范围')
            .fontSize(13)
            .fontColor(Color.White)
          Button('完成')
            .height(32)
            .padding({ left: 18, right: 18 })
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor('#3B82F6')
            .borderRadius(16)
            .onClick(() => this.finishMaskAdjust())
        }
        .padding({ left: 16, right: 8, top: 7, bottom: 7 })
        .borderRadius(24)
        .backgroundColor('#B3000000')
        .border({ width: 0.8, color: '#33FFFFFF' })
        .position({ x: '50%', y: '9%' })
        .translate({ x: '-50%' })
      }


    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .focusable(true)
    .defaultFocus(true)
    .onAreaChange((_oldVal: Area, newVal: Area) => {
      const w = Number(newVal.width);
      const h = Number(newVal.height);
      if (w > 0) this.viewportWidthVp = w;
      if (h > 0) this.viewportHeightVp = h;
    })
    .onKeyEvent((ev: KeyEvent) => this.handleKeyEvent(ev))
    .bindSheet(this.modalSheetVisible(), this.unifiedSheetBuilder(), {
      height: this.wideSheet() && this.drawerTab === 'settings'
        ? Math.min(520, Math.max(320, this.viewportHeightVp - 120))
        : this.modalSheetHeight(),
      dragBar: false,
      // 播放页抽屉里的字幕子页各自带返回/关闭，系统 X 会重复，统一由内容自绘
      showClose: false,
      preferType: this.wideSheet() ? SheetType.CENTER : SheetType.BOTTOM,
      width: this.wideSheet() ? 680 : undefined,
      backgroundColor: '#FF12151E',
      onDisappear: () => {
        this.subtitlePage = 'none';
        this.drawerTab = 'none';
        this.showControls = true;
        this.scheduleHideControls();
      }
    })
  }
}

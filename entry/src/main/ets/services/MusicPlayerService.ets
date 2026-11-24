import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import prismNative from 'libprismplayer.so';
import { AppConstants } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, WatchHistoryRecord } from '../common/Types';
import { AppStore } from './AppStore';
import { AVSessionService } from './AVSessionService';
import { RemoteSourceClient } from './RemoteSourceClient';

const LOG_TAG: string = 'PrismMusic';

export type MusicRepeatMode = 'off' | 'all' | 'one';

/** 进度落库节流：拖进度条时 timeUpdate 很密，没必要每次都写数据库。 */
const PROGRESS_SAVE_INTERVAL_MS: number = 5000;

interface ResolvedAudioSource {
  fd: number;
  size: number;
  url: string;
}

/**
 * 全局音乐播放器。
 *
 * 播放器实例挂在服务上而不是页面上：退出播放页、回到影库甚至切到后台都继续放，
 * 页面只是这唯一的播放现场的一个视图。视频播放由 PlayerPage 自己的引擎负责，
 * 两者通过「打开视频时暂停音乐」互斥，避免同时出声。
 */
@ObservedV2
export class MusicPlayerService {
  private static instance: MusicPlayerService | null = null;

  static getInstance(): MusicPlayerService {
    if (!MusicPlayerService.instance) {
      MusicPlayerService.instance = new MusicPlayerService();
    }
    return MusicPlayerService.instance;
  }

  private player: media.AVPlayer | null = null;
  private context: common.UIAbilityContext | null = null;
  private avSession: AVSessionService = new AVSessionService();
  private openedFd: number = -1;
  private proxyStreamId: string = '';
  private loadToken: number = 0;
  private lastSavedAt: number = 0;
  private pendingSeekMs: number = 0;
  private backgroundRunning: boolean = false;
  private durationSavedId: string = '';

  @Trace queue: MediaItem[] = [];
  @Trace currentIndex: number = -1;
  @Trace isPlaying: boolean = false;
  @Trace isBuffering: boolean = false;
  @Trace ready: boolean = false;
  @Trace positionMs: number = 0;
  @Trace durationMs: number = 0;
  @Trace repeatMode: MusicRepeatMode = 'all';
  @Trace errorText: string = '';

  get current(): MediaItem | null {
    if (this.currentIndex < 0 || this.currentIndex >= this.queue.length) return null;
    return this.queue[this.currentIndex];
  }

  get hasQueue(): boolean {
    return this.queue.length > 0 && this.currentIndex >= 0;
  }

  get progress(): number {
    if (this.durationMs <= 0) return 0;
    return Math.max(0, Math.min(1, this.positionMs / this.durationMs));
  }

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /** 换队列并起播；队列相同则只切歌，不重建播放器。 */
  async setQueue(queue: MediaItem[], startIndex: number = 0, autoplay: boolean = true): Promise<void> {
    if (queue.length === 0) return;
    const index = Math.max(0, Math.min(startIndex, queue.length - 1));
    this.queue = queue;
    if (autoplay) {
      await this.playIndex(index);
    } else {
      this.currentIndex = index;
      this.positionMs = 0;
      this.durationMs = queue[index].durationMs || 0;
    }
  }

  async playIndex(index: number): Promise<void> {
    if (index < 0 || index >= this.queue.length) return;
    const token = ++this.loadToken;
    if (this.current && this.positionMs > 0) {
      this.saveProgress(false);
    }
    const item = this.queue[index];
    hilog.debug(0x0001, LOG_TAG, 'play index=%{public}d title=%{public}s', index, item.title);
    this.currentIndex = index;
    this.positionMs = 0;
    this.durationMs = item.durationMs || 0;
    this.errorText = '';
    this.isBuffering = true;
    this.ready = false;

    const history = AppStore.getInstance().getHistoryForItem(item.id);
    const historyTotal = history ? (history.durationMs || item.durationMs) : item.durationMs;
    // 距离结尾不到 15s 就从头放：从 4:59 续播一首 4:59 的歌等于什么都没听到
    const nearEnd = historyTotal > 0 && history !== undefined && history.positionMs >= historyTotal - 15000;
    this.pendingSeekMs = history && !history.finished && history.positionMs > 3000 && !nearEnd
      ? history.positionMs
      : 0;

    try {
      const player = await this.ensurePlayer();
      if (token !== this.loadToken) return;
      if (player.state !== 'idle') {
        await player.reset();
      }
      if (token !== this.loadToken) return;
      await this.closeSource();

      const src = await this.resolveSource(item);
      if (token !== this.loadToken) {
        await this.closeSource();
        return;
      }
      if (src.fd >= 0) {
        player.fdSrc = { fd: src.fd, offset: 0, length: src.size };
      } else {
        player.url = src.url;
      }
      // fdSrc / url 的赋值在系统侧是异步落地的：必须等状态真的到 initialized 再 prepare，
      // 否则会撞上「The current state is idle」并被 AVPlayer 判为参数非法
      const initialized = await this.waitForState('initialized', 3000);
      if (token !== this.loadToken) return;
      if (!initialized) {
        throw new Error('音频源初始化超时');
      }
      await player.prepare();
      if (token !== this.loadToken) return;
      // prepare() 的 Promise 可能先于状态回调返回，真正起播前必须确认已经落到 prepared
      const prepared = await this.waitForState('prepared', 3000);
      if (token !== this.loadToken) return;
      if (!prepared) {
        throw new Error('音频解码准备超时');
      }
      // 先把长时任务和媒体会话挂上，再起播：否则用户一起播就切后台会丢掉后台播放资格
      await this.syncSession(true);
      await this.startBackground();
      await this.startPlayback(player, token);
      if (token !== this.loadToken) return;
      this.isPlaying = true;
      this.isBuffering = false;
      await this.syncSession(false);
    } catch (e) {
      if (token !== this.loadToken) return;
      const raw = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, LOG_TAG, 'play failed: %{public}s', raw);
      this.errorText = Formatters.toFriendlyError(raw, true);
      this.isPlaying = false;
      this.isBuffering = false;
      await this.closeSource();
      await this.stopBackground();
    }
  }

  async toggle(): Promise<void> {
    if (!this.current) return;
    if (this.isPlaying) {
      await this.pause(true);
    } else {
      await this.resume();
    }
  }

  async resume(): Promise<void> {
    if (!this.player) {
      if (this.hasQueue) await this.playIndex(this.currentIndex);
      return;
    }
    if (!this.ready) {
      if (this.hasQueue) await this.playIndex(this.currentIndex);
      return;
    }
    try {
      await this.player.play();
      this.isPlaying = true;
      await this.syncSession(false);
      await this.startBackground();
    } catch (_e) {
      // 状态机拒绝时用重载兜底（例如 completed 后重新播放）
      if (this.hasQueue) await this.playIndex(this.currentIndex);
    }
  }

  async pause(userInitiated: boolean = true): Promise<void> {
    hilog.debug(0x0001, LOG_TAG, 'pause requested user=%{public}s state=%{public}s',
      `${userInitiated}`, this.player ? this.player.state : 'none');
    if (!this.player) return;
    try {
      if (this.player.state === 'playing' || this.player.state === 'prepared' || this.player.state === 'paused') {
        await this.player.pause();
      }
    } catch (_e) {
      // Ignore transient state errors
    }
    this.isPlaying = false;
    this.saveProgress(false);
    await this.syncSession(false);
    if (userInitiated) {
      await this.stopBackground();
    }
  }

  async seekTo(positionMs: number): Promise<void> {
    if (!this.player || !this.ready) return;
    const target = Math.max(0, Math.min(positionMs, this.durationMs > 0 ? this.durationMs : positionMs));
    try {
      this.player.seek(target);
      this.positionMs = target;
      await this.syncSession(false);
    } catch (_e) {
      // Ignore seek errors on live/unseekable sources
    }
  }

  async next(auto: boolean = false): Promise<void> {
    if (this.queue.length === 0) return;
    if (this.repeatMode === 'one' && auto) {
      await this.playIndex(this.currentIndex);
      return;
    }
    const nextIndex = this.currentIndex + 1;
    if (nextIndex < this.queue.length) {
      await this.playIndex(nextIndex);
      return;
    }
    if (this.repeatMode === 'all' || !auto) {
      await this.playIndex(0);
      return;
    }
    await this.pause(true);
  }

  async prev(): Promise<void> {
    if (this.queue.length === 0) return;
    if (this.positionMs > 5000) {
      await this.seekTo(0);
      return;
    }
    const prevIndex = this.currentIndex > 0 ? this.currentIndex - 1 : this.queue.length - 1;
    await this.playIndex(prevIndex);
  }

  /** 从队列里移除某首歌（删除导入或清空时用）；当前曲被删则顺延。 */
  async removeFromQueue(itemId: string): Promise<void> {
    const idx = this.queue.findIndex(t => t.id === itemId);
    if (idx < 0) return;
    const wasCurrent = idx === this.currentIndex;
    this.queue = this.queue.filter(t => t.id !== itemId);
    if (this.queue.length === 0) {
      await this.stop();
      return;
    }
    if (wasCurrent) {
      await this.playIndex(Math.min(idx, this.queue.length - 1));
    } else if (idx < this.currentIndex) {
      this.currentIndex--;
    }
  }

  cycleRepeat(): MusicRepeatMode {
    this.repeatMode = this.repeatMode === 'all' ? 'one' : (this.repeatMode === 'one' ? 'off' : 'all');
    this.syncSession(false).catch(() => {});
    return this.repeatMode;
  }

  async stop(): Promise<void> {
    this.loadToken++;
    if (this.player) {
      try {
        await this.player.reset();
      } catch (_e) {
        // Ignore
      }
    }
    await this.closeSource();
    this.isPlaying = false;
    this.isBuffering = false;
    this.ready = false;
    this.positionMs = 0;
    this.durationMs = 0;
    this.queue = [];
    this.currentIndex = -1;
    await this.avSession.release();
    await this.stopBackground();
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player) return this.player;
    const created = await media.createAVPlayer();
    created.on('stateChange', (state: media.AVPlayerState) => this.onState(state));
    created.on('timeUpdate', (time: number) => {
      this.positionMs = time;
      if (this.isPlaying && Date.now() - this.lastSavedAt > PROGRESS_SAVE_INTERVAL_MS) {
        this.saveProgress(false);
      }
    });
    created.on('durationUpdate', (duration: number) => {
      if (duration <= 0) return;
      this.durationMs = duration;
      if (this.current && this.current.durationMs !== duration) this.current.durationMs = duration;
    });
    created.on('seekDone', (time: number) => {
      this.positionMs = time;
    });
    created.on('error', (err: BusinessError) => {
      hilog.error(0x0001, LOG_TAG, 'player error: %{public}s', err.message);
      this.errorText = Formatters.toFriendlyError(err.message, true);
      this.isPlaying = false;
      this.isBuffering = false;
    });
    created.on('audioInterrupt', (event: audio.InterruptEvent) => {
      hilog.debug(0x0001, LOG_TAG, 'audio interrupt hint=%{public}d force=%{public}d',
        event.hintType, event.forceType);
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.pause(false).catch(() => {});
      }
    });
    this.player = created;
    return created;
  }

  private onState(state: media.AVPlayerState): void {
    if (state === 'initialized') {
      if (this.player) {
        this.player.audioRendererInfo = {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          rendererFlags: 0
        };
      }
    } else if (state === 'prepared') {
      this.ready = true;
      this.isBuffering = false;
      if (this.pendingSeekMs > 0 && this.player) {
        const target = this.pendingSeekMs;
        this.pendingSeekMs = 0;
        this.player.seek(target);
      }
    } else if (state === 'playing') {
      this.isPlaying = true;
      this.isBuffering = false;
      this.ready = true;
      this.errorText = '';
      this.syncSession(false).catch(() => {});
    } else if (state === 'paused') {
      this.isPlaying = false;
      this.saveProgress(false);
      this.syncSession(false).catch(() => {});
    } else if (state === 'completed') {
      this.isPlaying = false;
      this.saveProgress(true);
      this.next(true).catch(() => {});
    } else if (state === 'error') {
      this.isPlaying = false;
      this.isBuffering = false;
    }
  }

  private waitForState(target: media.AVPlayerState, timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      if (this.player && this.player.state === target) {
        resolve(true);
        return;
      }
      const started = Date.now();
      const timer = setInterval(() => {
        if (this.player && this.player.state === target) {
          clearInterval(timer);
          resolve(true);
        } else if (Date.now() - started > timeoutMs) {
          clearInterval(timer);
          resolve(false);
        }
      }, 30);
    });
  }

  /** 切歌瞬间可能被音频焦点 / 会话状态打断，play 失败就等状态稳定后重试。 */
  private async startPlayback(player: media.AVPlayer, token: number): Promise<void> {
    let lastError: Error = new Error('播放启动失败');
    for (let attempt = 0; attempt < 3; attempt++) {
      if (token !== this.loadToken) return;
      try {
        await player.play();
        return;
      } catch (e) {
        lastError = e instanceof Error ? e : new Error(String(e));
        await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 160));
        const prepared = await this.waitForState('prepared', 1200);
        if (!prepared) {
          await this.waitForState('paused', 600);
        }
      }
    }
    throw lastError;
  }

  private async resolveSource(item: MediaItem): Promise<ResolvedAudioSource> {
    const raw = item.streamUrl || '';
    if (raw.startsWith('/') || raw.startsWith('file://') || raw.startsWith('content://') || raw.startsWith('datashare://')) {
      const file = fs.openSync(raw, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      this.openedFd = file.fd;
      return { fd: file.fd, size: stat.size, url: '' };
    }

    const store = AppStore.getInstance();
    const source: MediaSource | undefined = store.sources.find(s => s.id === item.sourceId);
    const resolved = await RemoteSourceClient.resolvePlayableStream(item, source);
    const playUrl = resolved.streamUrl;
    if (!RemoteSourceClient.needsRangeProxy(playUrl, source)) {
      return { fd: -1, size: 0, url: playUrl };
    }
    store.ensureNativeProxy();
    const streamId = `music_${Date.now()}`;
    const cfg = RemoteSourceClient.buildProxyConfig(playUrl, source);
    const proxied = prismNative.registerProxyStream(streamId, cfg);
    if (!proxied) {
      throw new Error('本地取流代理未就绪，无法播放该音频');
    }
    this.proxyStreamId = streamId;
    return { fd: -1, size: 0, url: proxied };
  }

  private async closeSource(): Promise<void> {
    if (this.openedFd >= 0) {
      try {
        fs.closeSync(this.openedFd);
      } catch (_e) {
        // Ignore
      }
      this.openedFd = -1;
    }
    if (this.proxyStreamId) {
      try {
        prismNative.unregisterProxyStream(this.proxyStreamId);
      } catch (_e) {
        // Ignore
      }
      this.proxyStreamId = '';
    }
  }

  private saveProgress(finished: boolean): void {
    const item = this.current;
    if (!item) return;
    this.lastSavedAt = Date.now();
    const total = this.durationMs > 0 ? this.durationMs : item.durationMs;
    if (total <= 0 && this.positionMs <= 0) return;
    if (total > 0 && this.durationSavedId !== item.id) {
      // 远端音频入库时时长未知：首次拿到真实时长后补写条目，队列和下次续播都用得上
      this.durationSavedId = item.id;
      if (item.durationMs !== total) item.durationMs = total;
      AppStore.getInstance().persistMediaItem(item);
    }
    const record: WatchHistoryRecord = {
      itemId: item.id,
      title: item.title,
      subtitleLabel: item.artist || item.album || '',
      posterUrl: item.posterUrl,
      streamUrl: item.streamUrl,
      sourceId: item.sourceId,
      positionMs: finished ? total : this.positionMs,
      durationMs: total,
      audioTrackIndex: -1,
      subtitleTrackIndex: -1,
      subtitleDelayMs: 0,
      playbackRate: 1.0,
      maskEnabled: -1,
      maskYTop: -1,
      maskYBottom: -1,
      updatedAt: Date.now(),
      finished
    };
    AppStore.getInstance().saveWatchProgress(record).catch(() => {});
  }

  private async syncSession(force: boolean): Promise<void> {
    const item = this.current;
    if (!this.context || !item) return;
    if (force) {
      const prev = this.queue.length > 1
        ? this.queue[(this.currentIndex - 1 + this.queue.length) % this.queue.length].id
        : '';
      const nextId = this.queue.length > 1
        ? this.queue[(this.currentIndex + 1) % this.queue.length].id
        : '';
      await this.avSession.startSession(
        this.context,
        item.id,
        item.title,
        item.artist || item.album || '',
        this.durationMs > 0 ? this.durationMs : item.durationMs,
        {
          onPlay: () => { this.resume().catch(() => {}); },
          onPause: () => { this.pause(false).catch(() => {}); },
          onSeek: (pos: number) => { this.seekTo(pos).catch(() => {}); },
          onNext: () => { this.next(false).catch(() => {}); },
          onPrevious: () => { this.prev().catch(() => {}); },
          onStop: () => { this.stop().catch(() => {}); }
        },
        'audio',
        'PrismMusicSession',
        {
          artist: item.artist || '',
          album: item.album || '',
          mediaImage: this.sessionImage(item),
          previousAssetId: prev,
          nextAssetId: nextId
        }
      );
    }
    await this.avSession.updatePlaybackState(this.isPlaying, this.positionMs, 1.0, this.sessionLoopMode());
  }

  /** 通知栏封面：沙箱里的封面转成 file://，网络封面交给系统自己取。 */
  private sessionImage(item: MediaItem): string {
    const poster = item.posterUrl || '';
    if (poster.startsWith('/')) return `file://${poster}`;
    if (poster.startsWith('file://') || poster.startsWith('http://') || poster.startsWith('https://')) {
      return poster;
    }
    return '';
  }

  private sessionLoopMode(): avSession.LoopMode {
    if (this.repeatMode === 'one') return avSession.LoopMode.LOOP_MODE_SINGLE;
    if (this.repeatMode === 'all') return avSession.LoopMode.LOOP_MODE_LIST;
    return avSession.LoopMode.LOOP_MODE_SEQUENCE;
  }

  private async startBackground(): Promise<void> {
    if (this.backgroundRunning || !this.context) return;
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: AppConstants.BUNDLE_NAME, abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        agent
      );
      this.backgroundRunning = true;
      hilog.info(0x0001, LOG_TAG, 'background task started');
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'background task start failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private async stopBackground(): Promise<void> {
    if (!this.backgroundRunning || !this.context) return;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch (_e) {
      // Ignore
    }
    this.backgroundRunning = false;
  }
}

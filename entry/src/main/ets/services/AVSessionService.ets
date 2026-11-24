import { avSession } from '@kit.AVSessionKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface AVSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onSeek: (positionMs: number) => void;
  onNext?: () => void;
  onPrevious?: () => void;
  onStop?: () => void;
}

/** 通知栏 / 锁屏 / 控制中心展示的曲目信息。 */
export interface AVSessionTrackInfo {
  artist?: string;
  album?: string;
  /** 本地封面路径或 http(s) 地址；没有就留空，媒体中心会退回应用图标 */
  mediaImage?: string;
  previousAssetId?: string;
  nextAssetId?: string;
}

export class AVSessionService {
  private session: avSession.AVSession | null = null;
  private callbacks: AVSessionCallbacks | null = null;
  private launchReady: boolean = false;

  async startSession(
    context: common.UIAbilityContext,
    assetId: string,
    title: string,
    subtitle: string,
    durationMs: number,
    callbacks: AVSessionCallbacks,
    sessionType: avSession.AVSessionType = 'video',
    sessionTag: string = 'PrismPlayerSession',
    track: AVSessionTrackInfo = {}
  ): Promise<void> {
    try {
      if (!this.session) {
        this.session = await avSession.createAVSession(context, sessionTag, sessionType);
        // 命令回调只挂一次，切歌只换 callbacks；重复 on 会让一次“下一首”跳好几首
        this.session.on('play', () => {
          if (this.callbacks) this.callbacks.onPlay();
        });
        this.session.on('pause', () => {
          if (this.callbacks) this.callbacks.onPause();
        });
        this.session.on('seek', (pos: number) => {
          if (this.callbacks) this.callbacks.onSeek(pos);
        });
        this.bindOptionalCommands();
        await this.session.activate();
      }
      this.callbacks = callbacks;

      const metadata: avSession.AVMetadata = {
        assetId,
        title,
        subtitle,
        artist: track.artist || '',
        album: track.album || '',
        duration: durationMs > 0 ? durationMs : 0,
        previousAssetId: track.previousAssetId || '',
        nextAssetId: track.nextAssetId || ''
      };
      if (track.mediaImage) {
        metadata.mediaImage = track.mediaImage;
      }
      await this.session.setAVMetadata(metadata);
      await this.attachLaunchAbility(context);
      hilog.debug(0x0001, 'PrismAvSession', 'session ready tag=%{public}s type=%{public}s title=%{public}s',
        sessionTag, sessionType, title);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0001, 'PrismAvSession', 'session setup failed code=%{public}d msg=%{public}s',
        err && err.code ? err.code : 0, err && err.message ? err.message : String(e));
    }
  }

  /** 上一首/下一首/停止在部分设备上不可用，单独吞掉，别影响播放/暂停。 */
  private bindOptionalCommands(): void {
    if (!this.session) return;
    try {
      this.session.on('playNext', () => {
        if (this.callbacks && this.callbacks.onNext) this.callbacks.onNext();
      });
    } catch (_e) {
      // 媒体卡片只显示播放/暂停
    }
    try {
      this.session.on('playPrevious', () => {
        if (this.callbacks && this.callbacks.onPrevious) this.callbacks.onPrevious();
      });
    } catch (_e) {
      // Ignore
    }
    try {
      this.session.on('stop', () => {
        if (this.callbacks && this.callbacks.onStop) this.callbacks.onStop();
      });
    } catch (_e) {
      // Ignore
    }
  }

  /** 点通知/锁屏卡片回到播放器；只挂一次。 */
  private async attachLaunchAbility(context: common.UIAbilityContext): Promise<void> {
    if (this.launchReady || !this.session) return;
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 100,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await this.session.setLaunchAbility(agent);
      this.launchReady = true;
    } catch (_e) {
      // 媒体中心仍能控制播放，只是点击不跳转
    }
  }

  async updatePlaybackState(
    isPlaying: boolean,
    positionMs: number,
    speed: number,
    loopMode: avSession.LoopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE
  ): Promise<void> {
    if (!this.session) return;
    try {
      const state: avSession.AVPlaybackState = {
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: Math.max(0, positionMs),
          updateTime: Date.now()
        },
        speed,
        loopMode
      };
      await this.session.setAVPlaybackState(state);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0001, 'PrismAvSession', 'state update failed code=%{public}d msg=%{public}s playing=%{public}s',
        err && err.code ? err.code : 0, err && err.message ? err.message : String(e), `${isPlaying}`);
    }
  }

  async release(): Promise<void> {
    if (!this.session) return;
    try {
      await this.session.deactivate();
      await this.session.destroy();
    } catch (_e) {
      // Ignore cleanup errors
    } finally {
      this.session = null;
      this.callbacks = null;
      this.launchReady = false;
    }
  }
}

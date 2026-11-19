import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';

export interface AVSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onSeek: (positionMs: number) => void;
}

export class AVSessionService {
  private session: avSession.AVSession | null = null;

  async startSession(
    context: common.UIAbilityContext,
    assetId: string,
    title: string,
    subtitle: string,
    durationMs: number,
    callbacks: AVSessionCallbacks
  ): Promise<void> {
    try {
      if (!this.session) {
        this.session = await avSession.createAVSession(context, 'PrismPlayerSession', 'video');
        this.session.on('play', () => callbacks.onPlay());
        this.session.on('pause', () => callbacks.onPause());
        this.session.on('seek', (pos: number) => callbacks.onSeek(pos));
        await this.session.activate();
      }
      const metadata: avSession.AVMetadata = {
        assetId,
        title,
        subtitle,
        duration: durationMs > 0 ? durationMs : 0
      };
      await this.session.setAVMetadata(metadata);
    } catch (_e) {
      // Non-fatal on environments without active media daemon
    }
  }

  async updatePlaybackState(isPlaying: boolean, positionMs: number, speed: number): Promise<void> {
    if (!this.session) return;
    try {
      const state: avSession.AVPlaybackState = {
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: Math.max(0, positionMs),
          updateTime: Date.now()
        },
        speed
      };
      await this.session.setAVPlaybackState(state);
    } catch (_e) {
      // Ignore transient state errors
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
    }
  }
}

/**
 * 应用接续（跨端迁移）的数据契约。
 *
 * 源端在 UIAbility.onContinue 里把播放现场写进 wantParam，目标端在 onCreate /
 * onNewWant 里从 want.parameters 读回并直接起播。载荷统一用一段 JSON 字符串承载，
 * 避免跨端序列化对象时出现字段类型漂移。
 */
export const CONTINUE_WANT_KEY: string = 'prismplayer.continue.payload';

export interface ContinuePayload {
  itemId: string;
  positionMs: number;
  audioTrackIndex: number;
  subtitleTrackIndex: number;
  subtitleDelayMs: number;
  playbackRate: number;
}

export class PlaybackHandoff {
  static write(wantParam: Record<string, Object>, payload: ContinuePayload): void {
    wantParam[CONTINUE_WANT_KEY] = JSON.stringify(payload);
  }

  static read(params?: Record<string, Object>): ContinuePayload | null {
    if (!params) return null;
    const raw: Object | undefined = params[CONTINUE_WANT_KEY];
    if (typeof raw !== 'string' || raw.length === 0) return null;
    try {
      const parsed = JSON.parse(raw) as ContinuePayload;
      if (!parsed || typeof parsed.itemId !== 'string' || parsed.itemId.length === 0) return null;
      return {
        itemId: parsed.itemId,
        positionMs: typeof parsed.positionMs === 'number' ? parsed.positionMs : 0,
        audioTrackIndex: typeof parsed.audioTrackIndex === 'number' ? parsed.audioTrackIndex : -1,
        subtitleTrackIndex: typeof parsed.subtitleTrackIndex === 'number' ? parsed.subtitleTrackIndex : -1,
        subtitleDelayMs: typeof parsed.subtitleDelayMs === 'number' ? parsed.subtitleDelayMs : 0,
        playbackRate: typeof parsed.playbackRate === 'number' && parsed.playbackRate > 0 ? parsed.playbackRate : 1.0
      };
    } catch (_e) {
      return null;
    }
  }
}

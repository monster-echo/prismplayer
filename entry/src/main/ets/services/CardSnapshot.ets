import { WatchHistoryRecord } from '../common/Types';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 服务卡片的数据快照。
 *
 * 卡片进程不能长期持有数据库连接，也不该在 onAddForm 里做异步 IO，所以主进程在每次
 * 进度落库后把「继续观看」这一屏算好、序列化成 JSON 塞进 preferences；卡片只读这一份。
 *
 * 关键约束：快照在写入时就已完成隐私过滤，且**不随保险库解锁而放行**——桌面是公共区域。
 */
export interface CardData {
  hasData: boolean;
  title: string;
  detail: string;
  percent: number;
  itemId: string;
  positionMs: number;
  /** 海报来源（http/https 才有意义），仅供主进程取图，卡片不用。 */
  posterUrl: string;
  /** 主进程落地的海报文件绝对路径。 */
  posterPath: string;
  /** 是否已有可用海报（有才在卡片上渲染图）。 */
  hasPoster: boolean;
}

export const CARD_SNAPSHOT_KEY: string = 'card.continueWatching';

export class CardSnapshot {
  static empty(): CardData {
    return {
      hasData: false, title: '', detail: '', percent: 0, itemId: '', positionMs: 0,
      posterUrl: '', posterPath: '', hasPoster: false
    };
  }

  /** 低于这个时长的条目（预告片、花絮、短视频）不配占据「继续观看」。 */
  private static readonly MIN_MEANINGFUL_MS: number = 5 * 60 * 1000;

  /**
   * @param history 播放历史（已按 updatedAt 倒序）
   * @param concealedIds 隐私空间内的条目 id 集合，任何情况下都不得出现在卡片上
   */
  static build(history: WatchHistoryRecord[], concealedIds: Set<string>): CardData {
    // 桌面上没有海报的条目就是一块黑板，所以「有封面」优先于「最近播放」
    const picked: WatchHistoryRecord | null =
      CardSnapshot.pick(history, concealedIds, CardSnapshot.MIN_MEANINGFUL_MS, true)
        ?? CardSnapshot.pick(history, concealedIds, CardSnapshot.MIN_MEANINGFUL_MS, false)
        ?? CardSnapshot.pick(history, concealedIds, 1, false);
    if (!picked) {
      hilog.info(0x0001, 'PrismCardPick', 'no candidate in %{public}d records', history.length);
      return CardSnapshot.empty();
    }
    hilog.info(0x0001, 'PrismCardPick', 'picked=%{public}s dur=%{public}d in %{public}d records',
      picked.itemId, picked.durationMs, history.length);
    return CardSnapshot.toCardData(picked);
  }

  /** 先找达到时长门槛的最近一条；一条都没有时再做兜底。 */
  private static pick(
    history: WatchHistoryRecord[],
    concealedIds: Set<string>,
    minDurationMs: number,
    requirePoster: boolean
  ): WatchHistoryRecord | null {
    for (let i = 0; i < history.length; i++) {
      const rec = history[i];
      if (rec.finished) continue;
      if (rec.durationMs < minDurationMs) continue;
      if (rec.positionMs <= 0) continue;
      if (concealedIds.has(rec.itemId)) continue;
      if (requirePoster && !CardSnapshot.hasUsablePoster(rec.posterUrl)) continue;
      return rec;
    }
    return null;
  }

  /** 只有能真正取到图的地址才算「有海报」，空串和相对路径都不算。 */
  private static hasUsablePoster(url?: string): boolean {
    if (!url) return false;
    return url.startsWith('http://') || url.startsWith('https://') || url.startsWith('local://');
  }

  private static toCardData(rec: WatchHistoryRecord): CardData {
    const percent: number = Math.max(0, Math.min(100, Math.round((rec.positionMs / rec.durationMs) * 100)));
    return {
      hasData: true,
      title: rec.title || '继续观看',
      detail: CardSnapshot.formatDetail(rec),
      percent,
      itemId: rec.itemId,
      positionMs: rec.positionMs,
      posterUrl: rec.posterUrl || '',
      posterPath: '',
      hasPoster: false
    };
  }

  static formatDetail(rec: WatchHistoryRecord): string {
    const totalMin: number = Math.floor(rec.durationMs / 60000);
    const doneMin: number = Math.floor(rec.positionMs / 60000);
    const tail: string = rec.subtitleLabel ? ` · ${rec.subtitleLabel}` : '';
    if (totalMin <= 0) return `已看 ${Math.round((rec.positionMs / rec.durationMs) * 100)}%${tail}`;
    return `${doneMin} / ${totalMin} 分钟${tail}`;
  }

  static toJson(data: CardData): string {
    return JSON.stringify(data);
  }

  static fromJson(raw?: string): CardData {
    if (!raw) return CardSnapshot.empty();
    try {
      const parsed = JSON.parse(raw) as CardData;
      if (!parsed || typeof parsed.title !== 'string') return CardSnapshot.empty();
      return {
        hasData: parsed.hasData === true,
        title: parsed.title,
        detail: typeof parsed.detail === 'string' ? parsed.detail : '',
        percent: typeof parsed.percent === 'number' ? parsed.percent : 0,
        itemId: typeof parsed.itemId === 'string' ? parsed.itemId : '',
        positionMs: typeof parsed.positionMs === 'number' ? parsed.positionMs : 0,
        posterUrl: typeof parsed.posterUrl === 'string' ? parsed.posterUrl : '',
        posterPath: typeof parsed.posterPath === 'string' ? parsed.posterPath : '',
        hasPoster: parsed.hasPoster === true
      };
    } catch (_e) {
      return CardSnapshot.empty();
    }
  }
}

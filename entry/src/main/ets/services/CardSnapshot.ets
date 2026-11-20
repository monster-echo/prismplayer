import { WatchHistoryRecord } from '../common/Types';

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
}

export const CARD_SNAPSHOT_KEY: string = 'card.continueWatching';

export class CardSnapshot {
  static empty(): CardData {
    return { hasData: false, title: '', detail: '', percent: 0, itemId: '', positionMs: 0 };
  }

  /**
   * @param history 播放历史（已按 updatedAt 倒序）
   * @param concealedIds 隐私空间内的条目 id 集合，任何情况下都不得出现在卡片上
   */
  static build(history: WatchHistoryRecord[], concealedIds: Set<string>): CardData {
    for (let i = 0; i < history.length; i++) {
      const rec = history[i];
      if (rec.finished) continue;
      if (rec.durationMs <= 0) continue;
      if (concealedIds.has(rec.itemId)) continue;
      const percent: number = Math.max(0, Math.min(100, Math.round((rec.positionMs / rec.durationMs) * 100)));
      return {
        hasData: true,
        title: rec.title || '继续观看',
        detail: CardSnapshot.formatDetail(rec),
        percent,
        itemId: rec.itemId,
        positionMs: rec.positionMs
      };
    }
    return CardSnapshot.empty();
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
        positionMs: typeof parsed.positionMs === 'number' ? parsed.positionMs : 0
      };
    } catch (_e) {
      return CardSnapshot.empty();
    }
  }
}

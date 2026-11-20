import { common } from '@kit.AbilityKit';
import { commentManager } from '@kit.AppGalleryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStore } from './AppStore';

const LOG_TAG: string = 'PrismReview';
const KEY_COMPLETED: string = 'review.completedCount';
const KEY_LAST_PROMPT: string = 'review.lastPromptAt';
const MIN_COMPLETED_BEFORE_PROMPT: number = 3;
const PROMPT_COOLDOWN_MS: number = 90 * 24 * 60 * 60 * 1000;

/**
 * 应用内评分入口。
 *
 * 商店评分是自然下载量的一阶变量，但这里只做「看完一部再问」：完成播放累计 3 次后才弹一次，
 * 之后 90 天内不再打扰。启动、首次播放、付费页都不弹。
 */
export class ReviewPrompt {
  static async onPlaybackFinished(store: AppStore, context: common.UIAbilityContext): Promise<void> {
    try {
      if (!store.privacyAccepted) return;
      const completed: number = (await store.getNumberPref(KEY_COMPLETED, 0)) + 1;
      await store.setNumberPref(KEY_COMPLETED, completed);
      if (completed < MIN_COMPLETED_BEFORE_PROMPT) return;

      const lastPromptAt: number = await store.getNumberPref(KEY_LAST_PROMPT, 0);
      if (lastPromptAt > 0 && Date.now() - lastPromptAt < PROMPT_COOLDOWN_MS) return;

      await store.setNumberPref(KEY_LAST_PROMPT, Date.now());
      await commentManager.showCommentDialog(context);
      hilog.info(0x0001, LOG_TAG, 'comment dialog shown after %{public}d completed playbacks', completed);
    } catch (e) {
      // Store not published yet, or the device has no AppGallery service: never block playback.
      hilog.warn(0x0001, LOG_TAG, 'showCommentDialog skipped: %{public}s', JSON.stringify(e));
    }
  }
}

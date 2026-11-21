import { common } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardData } from './CardSnapshot';

const LOG_TAG: string = 'PrismCardForm';

/** formImages 需要「有明确声明类型」的对象；卡片侧固定用 memory://poster 引用。 */
export class FormImageHolder {
  poster: number = -1;
}

export interface CardFormPayload {
  hasData: boolean;
  title: string;
  detail: string;
  percent: number;
  itemId: string;
  positionMs: number;
  posterUri: string;
  hasPoster: boolean;
  formImages?: FormImageHolder;
}

/**
 * 卡片数据的唯一构造入口。
 *
 * FormAbility（`onAddForm`/`onUpdateForm`）和主进程主动推送共用这一份，避免两处拼数据漂移。
 * 海报句柄由调用方决定生命周期：主进程 push 时自行 open/close，FormAbility 复用常驻句柄。
 */
export class CardFormData {
  static build(data: CardData, posterFd: number): formBindingData.FormBindingData {
    const payload: CardFormPayload = {
      hasData: data.hasData,
      title: data.hasData ? data.title : '还没有观影记录',
      detail: data.hasData ? data.detail : '播放任意影片后回来看看',
      percent: data.percent,
      itemId: data.itemId,
      positionMs: data.positionMs,
      posterUri: data.posterPath ? `file://${data.posterPath}` : '',
      hasPoster: data.hasPoster && posterFd >= 0
    };
    if (posterFd >= 0) {
      const holder = new FormImageHolder();
      holder.poster = posterFd;
      payload.formImages = holder;
    }
    return formBindingData.createFormBindingData(payload);
  }

  /**
   * 把最新快照推给桌面上已添加的卡片。
   * 找不到卡片、或系统不给权限时静默返回，不影响播放链路。
   */
  static async push(context: common.Context, data: CardData): Promise<number> {
    let forms: formInfo.RunningFormInfo[] = [];
    try {
      forms = await formProvider.getPublishedRunningFormInfos();
    } catch (e) {
      hilog.debug(0x0001, LOG_TAG, 'no running forms: %{public}s', JSON.stringify(e));
      return 0;
    }
    hilog.info(0x0001, LOG_TAG, 'push forms=%{public}d hasPoster=%{public}s path=%{public}s',
      forms.length, `${data.hasPoster}`, data.posterPath ? 'yes' : 'no');
    if (forms.length === 0) return 0;

    let fd: number = -1;
    if (data.hasPoster && data.posterPath) {
      try {
        fd = fs.openSync(data.posterPath, fs.OpenMode.READ_ONLY).fd;
      } catch (_e) {
        fd = -1;
      }
    }
    const binding: formBindingData.FormBindingData = CardFormData.build(data, fd);
    let updated: number = 0;
    for (let i = 0; i < forms.length; i++) {
      try {
        await formProvider.updateForm(forms[i].formId, binding);
        updated++;
      } catch (e) {
        hilog.warn(0x0001, LOG_TAG, 'update form %{public}s failed: %{public}s',
          forms[i].formId, JSON.stringify(e));
      }
    }
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (_e) {
        // Ignore
      }
    }
    return updated;
  }
}

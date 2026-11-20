import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';
import { CardData, CardSnapshot, CARD_SNAPSHOT_KEY } from '../services/CardSnapshot';

const LOG_TAG: string = 'PrismFormAbility';

/**
 * 「继续观看」卡片的 data provider。
 *
 * 只读 preferences 里的快照，不碰数据库、不发起网络请求：卡片代码跑在独立进程，
 * 任何一次 onAddForm 卡住都会让桌面留白。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  private readSnapshot(formId: string): CardData {
    try {
      const prefs: preferences.Preferences =
        preferences.getPreferencesSync(this.context, { name: AppConstants.PREFS_NAME });
      const raw: string = prefs.getSync(CARD_SNAPSHOT_KEY, '') as string;
      return CardSnapshot.fromJson(raw);
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'read snapshot failed: %{public}s', JSON.stringify(e));
      return CardSnapshot.empty();
    }
  }

  private toBindingData(data: CardData): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      hasData: data.hasData,
      title: data.hasData ? data.title : '还没有观影记录',
      detail: data.hasData ? data.detail : '播放任意影片后回来看看',
      percent: data.percent,
      itemId: data.itemId,
      positionMs: data.positionMs
    });
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = want.parameters ? (want.parameters['ohos.extra.param.key.form_identity'] as string) : '';
    const data: CardData = this.readSnapshot(formId);
    return this.toBindingData(data);
  }

  onUpdateForm(formId: string): void {
    const data: CardData = this.readSnapshot(formId);
    formProvider.updateForm(formId, this.toBindingData(data)).catch((e: Error) => {
      hilog.warn(0x0001, LOG_TAG, 'updateForm failed: %{public}s', e.message);
    });
  }

  onFormEvent(formId: string, message: string): void {
    if (message === 'refresh') {
      this.onUpdateForm(formId);
    }
  }

  onRemoveForm(formId: string): void {
    hilog.info(0x0001, LOG_TAG, 'form removed: %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}

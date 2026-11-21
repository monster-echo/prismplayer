import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';
import { CardData, CardSnapshot, CARD_SNAPSHOT_KEY } from '../services/CardSnapshot';
import { CardFormData } from '../services/CardFormData';

const LOG_TAG: string = 'PrismFormAbility';


/**
 * 「继续观看」卡片的 data provider。
 *
 * 只读 preferences 里的快照，不碰数据库、不发起网络请求：卡片代码跑在独立进程，
 * 任何一次 onAddForm 卡住都会让桌面留白。海报由主进程提前落盘，这里只负责开文件句柄。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  private posterFd: number = -1;
  private posterPath: string = '';

  private readSnapshot(): CardData {
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

  /** 同一个进程内复用句柄；卡片更新频繁时避免反复 open/close。 */
  private openPoster(data: CardData): number {
    if (!data.posterPath) return -1;
    if (this.posterFd >= 0 && this.posterPath === data.posterPath) return this.posterFd;
    this.closePoster();
    try {
      const file = fs.openSync(data.posterPath, fs.OpenMode.READ_ONLY);
      this.posterFd = file.fd;
      this.posterPath = data.posterPath;
      return this.posterFd;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'open poster failed: %{public}s', JSON.stringify(e));
      return -1;
    }
  }

  private closePoster(): void {
    if (this.posterFd < 0) return;
    try {
      fs.closeSync(this.posterFd);
    } catch (_e) {
      // Ignore
    }
    this.posterFd = -1;
    this.posterPath = '';
  }

  private toBindingData(data: CardData): formBindingData.FormBindingData {
    return CardFormData.build(data, this.openPoster(data));
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    return this.toBindingData(this.readSnapshot());
  }

  onUpdateForm(formId: string): void {
    const data: CardData = this.readSnapshot();
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
    this.closePoster();
    hilog.info(0x0001, LOG_TAG, 'form removed: %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}

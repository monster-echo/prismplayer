import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';

const DOMAIN: number = 0x0001;
const LOG_TAG: string = 'PrismShareExt';

/** 分享面板把内容放在 want.parameters 里，键名各应用不一，因此按内容找链接而不是按键名。 */

/**
 * 系统分享目标。
 *
 * 用户在任意应用里点「分享」就能把链接丢给棱镜播放器：这里只负责把链接捞出来，
 * 拉起主应用后立刻结束会话，不在分享面板里停留。
 */
export default class ShareExtAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    const url: string = ShareExtAbility.findUrl(want);
    hilog.info(DOMAIN, LOG_TAG, 'session url=%{public}s', url ? url.substring(0, 48) : 'none');
    if (!url) {
      session.terminateSelf().catch((e: Error) => {
        hilog.warn(DOMAIN, LOG_TAG, 'terminate failed: %{public}s', e.message);
      });
      return;
    }

    const params: Record<string, Object> = {};
    params['sharedUrl'] = url;
    const target: Want = {
      bundleName: AppConstants.BUNDLE_NAME,
      abilityName: 'EntryAbility',
      parameters: params
    };
    this.context.startAbility(target)
      .then(() => {
        session.terminateSelf().catch(() => {});
      })
      .catch((e: Error) => {
        hilog.warn(DOMAIN, LOG_TAG, 'startAbility failed: %{public}s', e.message);
        session.terminateSelf().catch(() => {});
      });
  }

  /** 从分享参数里挑出第一条可播放链接：字符串、字符串数组、uri 数组都覆盖。 */
  private static findUrl(want: Want): string {
    const fromUri: string = ShareExtAbility.pickUrl(want.uri);
    if (fromUri) return fromUri;
    const params = want.parameters;
    if (!params) return '';
    const keys: string[] = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      const value: Object = params[keys[i]] as Object;
      const direct: string = ShareExtAbility.pickUrl(value as string);
      if (direct) return direct;
      if (Array.isArray(value)) {
        const list = value as Object[];
        for (let j = 0; j < list.length; j++) {
          const nested: string = ShareExtAbility.pickUrl(list[j] as string);
          if (nested) return nested;
        }
      }
    }
    return '';
  }

  private static pickUrl(raw?: string): string {
    if (!raw || typeof raw !== 'string') return '';
    const match: RegExpMatchArray | null = raw.match(/https?:\/\/[^\s"'<>]+/);
    if (!match) return '';
    return match[0].replace(/[)\]）】>,，。;；]+$/, '');
  }
}

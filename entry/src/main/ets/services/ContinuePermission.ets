import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStore } from './AppStore';

const LOG_TAG: string = 'PrismContinue';
const PERM: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';
const KEY_ASKED: string = 'perm.continueAsked';

/**
 * 应用接续所需权限。
 *
 * 只在用户第一次进入播放页时问一次：那个时刻「可能要把这一部接到别的设备上看」是能自解释的，
 * 放在启动页问则完全无上下文。被拒绝后不再重复打扰，接续入口保留但会在迁移时被系统拦下。
 */
export class ContinuePermission {
  static async ensure(context: common.UIAbilityContext, store: AppStore): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = context.applicationInfo.accessTokenId;
      const status = await atManager.checkAccessToken(tokenId, PERM);
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) return true;

      const asked: number = await store.getNumberPref(KEY_ASKED, 0);
      if (asked === 1) return false;
      await store.setNumberPref(KEY_ASKED, 1);

      const perms: Permissions[] = [PERM];
      const result = await atManager.requestPermissionsFromUser(context, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      hilog.info(0x0001, LOG_TAG, 'DISTRIBUTED_DATASYNC granted=%{public}s', `${granted}`);
      return granted;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'ensure permission failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }
}

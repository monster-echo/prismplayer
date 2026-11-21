import { fileShare } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const LOG_TAG: string = 'PrismLocalAccess';
/** 一次性提交太多 uri 会拖慢系统侧授权，分批走。 */
const CHUNK: number = 50;

/**
 * 本机视频的访问授权。
 *
 * 手机上不存在「扫一遍拿全部视频」的权限（READ_IMAGEVIDEO 是 system_basic 受限权限），
 * 所以本机视频走的是「用户通过文件选择器授权 → 把授权持久化」这条路。
 * 关键点：persistPermission 只做一次，之后每次启动都要 activatePermission 才会真正生效，
 * 否则重启后所有本机条目都会变成打不开的死链。
 */
export class LocalAccess {
  private static policies(uris: string[]): fileShare.PolicyInfo[] {
    const list: fileShare.PolicyInfo[] = [];
    for (let i = 0; i < uris.length; i++) {
      const info: fileShare.PolicyInfo = { uri: uris[i], operationMode: fileShare.OperationMode.READ_MODE };
      list.push(info);
    }
    return list;
  }

  /** 首次导入时调用：把这次选择换来的临时授权固化下来。 */
  static async persist(uris: string[]): Promise<void> {
    if (uris.length === 0) return;
    for (let start = 0; start < uris.length; start += CHUNK) {
      const slice: string[] = uris.slice(start, start + CHUNK);
      try {
        await fileShare.persistPermission(LocalAccess.policies(slice));
      } catch (e) {
        hilog.warn(DOMAIN, LOG_TAG, 'persist failed: %{public}s', JSON.stringify(e));
      }
    }
  }

  /** 每次启动都要调用：把已固化的授权重新激活，否则访问会被系统拒绝。 */
  static async activate(uris: string[]): Promise<void> {
    if (uris.length === 0) return;
    for (let start = 0; start < uris.length; start += CHUNK) {
      const slice: string[] = uris.slice(start, start + CHUNK);
      try {
        await fileShare.activatePermission(LocalAccess.policies(slice));
      } catch (e) {
        hilog.debug(DOMAIN, LOG_TAG, 'activate skipped: %{public}s', JSON.stringify(e));
      }
    }
  }
}

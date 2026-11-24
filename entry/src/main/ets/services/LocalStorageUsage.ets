import { common } from '@kit.AbilityKit';
import { fileIo as fs, statfs } from '@kit.CoreFileKit';

@ObservedV2
export class LocalStorageUsageInfo {
  /** 应用数据（filesDir）+ 缓存 */
  @Trace appBytes: number = 0;
  /** 应用缓存 */
  @Trace cacheBytes: number = 0;
  /** 设备可用空间 */
  @Trace freeBytes: number = 0;
  /** 设备总空间 */
  @Trace totalBytes: number = 0;
}

/**
 * 设置页「存储」用的本地占用统计。
 * 只遍历应用沙箱，不依赖系统统计服务，拿不到的项按 0 处理。
 */
export class LocalStorageUsage {
  static async collect(context: common.UIAbilityContext): Promise<LocalStorageUsageInfo> {
    const filesBytes = LocalStorageUsage.pathSize(context.filesDir, 0);
    const cacheBytes = LocalStorageUsage.pathSize(context.cacheDir, 0);

    const info = new LocalStorageUsageInfo();
    info.appBytes = filesBytes + cacheBytes;
    info.cacheBytes = cacheBytes;
    try {
      info.freeBytes = statfs.getFreeSizeSync(context.filesDir);
      info.totalBytes = statfs.getTotalSizeSync(context.filesDir);
    } catch (_e) {
      // 拿不到容量时 UI 显示「—」
    }
    return info;
  }

  private static pathSize(path: string, depth: number): number {
    if (depth > 4) return 0;
    let names: string[] = [];
    try {
      names = fs.listFileSync(path);
    } catch (_e) {
      return 0;
    }
    let total = 0;
    for (let i = 0; i < names.length; i++) {
      const child = `${path}/${names[i]}`;
      try {
        const st = fs.lstatSync(child);
        if (st.isSymbolicLink()) continue;
        total += st.isDirectory() ? LocalStorageUsage.pathSize(child, depth + 1) : st.size;
      } catch (_e) {
        // 跳过无权限或已消失的文件
      }
    }
    return total;
  }
}

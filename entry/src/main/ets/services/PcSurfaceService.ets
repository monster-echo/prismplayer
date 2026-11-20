import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { quickBarManager, statusBarManager } from '@kit.DeskTopExtensionKit';

const LOG_TAG: string = 'PrismPcSurface';
const QUICK_CATEGORY_NAME: string = 'PrismPlayer';
const CONTINUE_TASK_NAME: string = '继续观看';

/**
 * 鸿蒙 PC（2in1）系统级入口。
 *
 * 播放中把 PrismPlayer 常驻到系统状态栏（图标 + 悬停片名 + 右键菜单），并在快捷栏维护
 * 唯一一条「继续观看」任务。两处都是零投放曝光面，手机上所有调用都会被能力探测跳过。
 */
export class PcSurfaceService {
  private static iconWhite: image.PixelMap | null = null;
  private static iconBlack: image.PixelMap | null = null;
  private static statusBarShown: boolean = false;
  private static hoverTips: string = '';
  private static quickBarCategoryId: number = -1;

  private static async loadIcon(ctx: common.UIAbilityContext, res: Resource): Promise<image.PixelMap | null> {
    try {
      const buffer: Uint8Array = ctx.resourceManager.getMediaContentSync(res.id);
      const source: image.ImageSource = image.createImageSource(buffer.buffer as ArrayBuffer);
      return await source.createPixelMap({ desiredSize: { width: 64, height: 64 } });
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'load icon failed: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  private static async ensureIcons(ctx: common.UIAbilityContext): Promise<boolean> {
    if (PcSurfaceService.iconWhite && PcSurfaceService.iconBlack) return true;
    PcSurfaceService.iconWhite = await PcSurfaceService.loadIcon(ctx, $r('app.media.foreground'));
    PcSurfaceService.iconBlack = PcSurfaceService.iconWhite;
    return PcSurfaceService.iconWhite !== null;
  }

  /** 播放开始时把图标挂进状态栏；同一时刻只会存在一个。 */
  static async showNowPlaying(ctx: common.UIAbilityContext, title: string, detail: string): Promise<void> {
    try {
      const supported = await statusBarManager.isStatusBarCapabilitySupported(ctx);
      if (!supported) return;
      if (!(await PcSurfaceService.ensureIcons(ctx))) return;

      const icons: statusBarManager.StatusBarIcon = {
        white: PcSurfaceService.iconWhite as image.PixelMap,
        black: PcSurfaceService.iconBlack as image.PixelMap
      };
      const menuItem: statusBarManager.StatusBarMenuItem = {
        title: '回到播放',
        menuCode: 'resume',
        menuAction: { abilityName: 'EntryAbility', moduleName: 'entry', menuCode: 'resume' }
      };
      const libraryItem: statusBarManager.StatusBarMenuItem = {
        title: '打开媒体库',
        menuCode: 'library',
        menuAction: { abilityName: 'EntryAbility', moduleName: 'entry', menuCode: 'library' }
      };
      const item: statusBarManager.StatusBarItem = {
        icons,
        hoverTips: title,
        statusBarGroupMenu: [[menuItem, libraryItem]],
        quickOperation: { title: '正在播放', height: 200, abilityName: 'EntryAbility', moduleName: 'entry' }
      };
      statusBarManager.addToStatusBar(ctx, item);
      PcSurfaceService.statusBarShown = true;
      PcSurfaceService.hoverTips = title;
      hilog.info(0x0001, LOG_TAG, 'status bar item added');
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'addToStatusBar failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 只刷新悬停片名，避免每次进度变化都重建图标。 */
  static async updateNowPlayingTitle(ctx: common.UIAbilityContext, title: string): Promise<void> {
    if (!PcSurfaceService.statusBarShown || title === PcSurfaceService.hoverTips) return;
    try {
      await statusBarManager.updateStatusBarHoverTips(ctx, title);
      PcSurfaceService.hoverTips = title;
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'update hover tips failed: %{public}s', JSON.stringify(e));
    }
  }

  static async hideNowPlaying(ctx: common.UIAbilityContext): Promise<void> {
    if (!PcSurfaceService.statusBarShown) return;
    try {
      statusBarManager.removeFromStatusBar(ctx);
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'removeFromStatusBar failed: %{public}s', JSON.stringify(e));
    }
    PcSurfaceService.statusBarShown = false;
    PcSurfaceService.hoverTips = '';
  }

  /** 快捷栏「继续观看」任务：整个应用只保留一条，内容随播放进度刷新。 */
  static async syncContinueTask(
    ctx: common.UIAbilityContext,
    title: string,
    detail: string,
    itemId: string,
    positionMs: number
  ): Promise<void> {
    if (!title) return;
    try {
      const supported = await quickBarManager.isQuickBarCapabilitySupported(ctx);
      if (!supported) return;

      if (PcSurfaceService.quickBarCategoryId < 0) {
        const categories: quickBarManager.CustomCategory[] = await quickBarManager.getCustomCategories(ctx);
        let category: quickBarManager.CustomCategory | undefined =
          categories.find((c: quickBarManager.CustomCategory) => c.categoryName === QUICK_CATEGORY_NAME);
        if (!category) {
          category = await quickBarManager.addCustomCategory(ctx, QUICK_CATEGORY_NAME);
        }
        PcSurfaceService.quickBarCategoryId = category.categoryId;
      }

      const info: quickBarManager.QuickTaskInfo = {
        taskName: CONTINUE_TASK_NAME,
        abilityName: 'EntryAbility',
        moduleName: 'entry',
        taskDetail: detail,
        parameters: [
          { key: 'menuCode', value: 'resume' },
          { key: 'itemId', value: itemId },
          { key: 'positionMs', value: `${Math.round(positionMs)}` }
        ]
      };
      const tasks: quickBarManager.QuickTask[] =
        await quickBarManager.getTasksFromCategory(ctx, PcSurfaceService.quickBarCategoryId);
      const existing = tasks.find((t: quickBarManager.QuickTask) => t.taskInfo.taskName === CONTINUE_TASK_NAME);
      if (existing) {
        await quickBarManager.updateQuickTask(ctx, {
          taskId: existing.taskId,
          categoryId: existing.categoryId,
          taskInfo: info
        });
      } else {
        await quickBarManager.addQuickTask(ctx, PcSurfaceService.quickBarCategoryId, info);
      }
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'sync quick bar task failed: %{public}s', JSON.stringify(e));
    }
  }
}

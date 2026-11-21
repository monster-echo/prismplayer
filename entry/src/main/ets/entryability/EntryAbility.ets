import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants, BreakpointType } from '../common/Constants';
import { Layout } from '../common/Layout';
import { ThemeManager } from '../common/ThemeManager';
import { OnlineMediaParams, ThemeMode } from '../common/Types';
import { AppStore } from '../services/AppStore';
import { ContinuePayload, PlaybackHandoff } from '../services/PlaybackHandoff';
import { ShareService } from '../services/ShareService';

const DOMAIN = 0x0001;

/**
 * 应用入口。
 *
 * 除三端断点外，这里负责四类「外部唤起」：系统打开方式（want.uri 文件）、应用接续
 * （onContinue / onWindowStageRestore）、分享与 App Linking 回落，以及鸿蒙 PC 状态栏 /
 * 快捷栏 / 桌面快捷方式传来的 menuCode。全部先暂存、等媒体库加载完再执行。
 */
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private pendingContinue: ContinuePayload | null = null;
  /** 分享扩展送进来的链接，等 store 就绪后跳「视频解析」页。 */
  private pendingUrl: string = '';
  private pendingMenuCode: string = '';
  private pendingItemId: string = '';
  private pendingPositionMs: number = 0;
  private storeReady: boolean = false;
  private flushing: boolean = false;

  /**
   * 首帧前同步读主题：异步 AppStore.init 落地前，界面会先按系统色渲染一帧浅色，
   * 用户看到的就是「先白后黑」。这里直接用 Preferences 同步接口取值，
   * 在 loadContent 之前把 setColorMode 定下来。
   */
  private readSavedTheme(): ThemeMode {
    try {
      const store = preferences.getPreferencesSync(this.context, { name: AppConstants.PREFS_NAME });
      const value = store.getSync('themeMode', 'system');
      if (value === 'light' || value === 'dark' || value === 'system') {
        return value as ThemeMode;
      }
    } catch (_e) {
      // 首次启动或读失败：跟随系统
    }
    return 'system';
  }

  private updateBreakpoint(widthPx: number, heightPx: number = 0): void {
    try {
      const d = display.getDefaultDisplaySync();
      const density = d.densityPixels > 0 ? d.densityPixels : 2;
      const widthVp = widthPx / density;
      const heightVp = heightPx > 0 ? (heightPx / density) : 0;
      const isLandscape = heightPx > 0 ? (widthPx > heightPx) : (widthVp >= 600);
      // 断点只认窗口宽度：sm < 600 ≤ md < 840 ≤ lg < 1440 ≤ xl，带 16vp 滞回防折叠抖动
      const bp: BreakpointType = Layout.resolveBreakpoint(widthVp, AppStore.getInstance().currentBreakpoint);
      AppStorage.setOrCreate('currentBreakpoint', bp);
      AppStorage.setOrCreate('windowWidthVp', Math.round(widthVp));
      AppStorage.setOrCreate('windowHeightVp', Math.round(heightVp));
      AppStorage.setOrCreate('isLandscape', isLandscape);
      AppStore.getInstance().currentBreakpoint = bp;
      AppStore.getInstance().isLandscape = isLandscape;
      AppStore.getInstance().windowWidthVp = Math.round(widthVp);
      AppStore.getInstance().windowHeightVp = Math.round(heightVp);
      hilog.debug(DOMAIN, 'PrismAbility', 'layout bp=%{public}s width=%{public}d height=%{public}d vp',
        bp, Math.round(widthVp), Math.round(heightVp));
    } catch (_e) {
      AppStorage.setOrCreate('currentBreakpoint', 'sm');
      AppStorage.setOrCreate('isLandscape', false);
      AppStore.getInstance().windowWidthVp = 360;
      AppStore.getInstance().windowHeightVp = 780;
    }
  }

  /** 2in1 / 平板：给窗口一个最小尺寸，避免被拖到手机宽度以下破版。 */
  private applyWindowLimits(win: window.Window): void {
    const type: string = deviceInfo.deviceType;
    if (type !== '2in1' && type !== 'tablet') return;
    try {
      const d = display.getDefaultDisplaySync();
      const density = d.densityPixels > 0 ? d.densityPixels : 2;
      const limits: window.WindowLimits = {
        minWidth: Math.round(360 * density),
        minHeight: Math.round(480 * density)
      };
      win.setWindowLimits(limits).catch(() => {});
    } catch (_e) {
      // Non-fatal
    }
  }

  private readParam(want: Want, key: string): string {
    if (!want.parameters) return '';
    const value: Object | undefined = want.parameters[key];
    // 卡片 postCardAction / 快捷栏 WantParams 可能带数字，统一转成字符串再解析
    if (typeof value === 'string') return value;
    if (typeof value === 'number') return `${value}`;
    return '';
  }

  private readParamNumber(want: Want, key: string): number {
    const raw: string = this.readParam(want, key);
    if (!raw) return 0;
    const parsed: number = Number(raw);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  /** 解析并暂存这一次启动携带的外部意图。 */
  private intakeIntent(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const uri: string = want.uri ? want.uri : '';
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      const target = ShareService.parseLink(uri);
      if (target) {
        this.pendingMenuCode = 'link';
        this.pendingItemId = target.itemId;
        this.pendingPositionMs = target.positionMs;
      }
    } else if (uri) {
      AppStore.getInstance().handleIncomingFileWant(uri);
    }

    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      const payload = PlaybackHandoff.read(want.parameters);
      if (payload) {
        this.pendingContinue = payload;
        return;
      }
    }

    // 分享扩展送进来的链接：直接进「视频解析」页并预填
    const sharedUrl: string = this.readParam(want, 'sharedUrl');
    if (sharedUrl) {
      this.pendingUrl = sharedUrl;
      this.pendingMenuCode = 'online';
      return;
    }

    const menuCode: string = this.readParam(want, 'menuCode');
    if (menuCode) {
      this.pendingMenuCode = menuCode;
      this.pendingItemId = this.readParam(want, 'itemId');
      this.pendingPositionMs = this.readParamNumber(want, 'positionMs');
    }
  }

  /** 执行意图。媒体库未加载完之前不允许执行，否则 itemId 解析不到条目。 */
  private async flushIntents(): Promise<void> {
    if (this.flushing || !this.storeReady) return;
    this.flushing = true;
    const store = AppStore.getInstance();
    try {
      if (this.pendingContinue) {
        const payload = this.pendingContinue;
        this.pendingContinue = null;
        const ok = await store.requestResumePlayback(payload.itemId, payload.positionMs);
        hilog.info(DOMAIN, 'PrismAbility', 'continuation restore ok=%{public}s', `${ok}`);
        if (ok) return;
      }

      const code: string = this.pendingMenuCode;
      if (code) {
        this.pendingMenuCode = '';
        if (code === 'link' || code === 'card') {
          if (this.pendingItemId) {
            await store.requestResumePlayback(this.pendingItemId, this.pendingPositionMs);
          }
          return;
        }
        if (code === 'resume' || code === 'continue') {
          if (this.pendingItemId) {
            await store.requestResumePlayback(this.pendingItemId, this.pendingPositionMs);
          } else {
            await store.requestContinueWatching();
          }
          return;
        }
        if (code === 'library') {
          store.requestTab(1);
          return;
        }
        if (code === 'online' && this.pendingUrl) {
          const params: OnlineMediaParams = { clipboardUrl: this.pendingUrl };
          this.pendingUrl = '';
          store.requestTab(0);
          store.requestRoute('pages/OnlineMediaPage', params);
          return;
        }
      }

      // 首次安装：接住「点了分享链接才来」的那次目标
      const linkTarget = await ShareService.popPendingLink();
      if (linkTarget) {
        await store.requestResumePlayback(linkTarget.itemId, linkTarget.positionMs);
      }
    } finally {
      this.flushing = false;
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'PrismAbility', 'onCreate');
    AppStorage.setOrCreate('currentBreakpoint', 'sm');
    // 尽早定色：越早在 onCreate 里 setColorMode，窗口创建时资源限定词越可能已经切好
    ThemeManager.init(this.context.getApplicationContext(), null);
    const bootTheme = this.readSavedTheme();
    hilog.info(DOMAIN, 'PrismAbility', 'boot theme=%{public}s', bootTheme);
    ThemeManager.applyMode(bootTheme);
    this.intakeIntent(want, launchParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.intakeIntent(want, launchParam);
    this.flushIntents().catch((e: Error) => {
      hilog.warn(DOMAIN, 'PrismAbility', 'flush intents failed: %{public}s', e.message);
    });
  }

  /** 源端：系统询问能否迁移时，把当前播放现场写进 wantParam。 */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    const payload: ContinuePayload | null = AppStore.getInstance().getLivePlayback();
    if (!payload) return AbilityConstant.OnContinueResult.REJECT;
    try {
      PlaybackHandoff.write(wantParam, payload);
      hilog.info(DOMAIN, 'PrismAbility', 'onContinue item=%{public}s pos=%{public}d',
        payload.itemId, Math.round(payload.positionMs));
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (e) {
      hilog.warn(DOMAIN, 'PrismAbility', 'onContinue failed: %{public}s', JSON.stringify(e));
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  private setupWindowStage(windowStage: window.WindowStage): void {
    ThemeManager.init(this.context.getApplicationContext(), null);

    windowStage.getMainWindow((err, win) => {
      const errCode = err ? err.code : 0;
      if (errCode === 0 && win) {
        this.mainWindow = win;
        ThemeManager.init(this.context.getApplicationContext(), win);
        // 窗口创建会把 colorMode 打回系统色（实测 6ms 后变回 light），这里重新定色
        ThemeManager.applyMode(this.readSavedTheme());
        this.applyWindowLimits(win);
        try {
          const props = win.getWindowProperties();
          this.updateBreakpoint(props.windowRect.width, props.windowRect.height);
          win.on('windowSizeChange', (size) => {
            this.updateBreakpoint(size.width, size.height);
          });
        } catch (_e) {
          // Non-fatal
        }
        ThemeManager.applyMode(AppStore.getInstance().settings.themeMode);
      }
    });

    AppStore.getInstance().init(this.context).then(() => {
      this.storeReady = true;
      this.flushing = false;
      ThemeManager.applyMode(AppStore.getInstance().settings.themeMode);
      return this.flushIntents();
    }).catch((e: Error) => {
      hilog.error(DOMAIN, 'PrismAbility', 'AppStore init failed: %{public}s', e.message);
    });

    // setColorMode 到资源限定词生效之间有一两帧延迟：轮询到实际生效后再 loadContent，
    // 否则用户会先看到浅色首帧再被刷成深色。启动窗口已是深色底，过渡无感。
    // 窗口创建后的 200~300ms 内系统还会推一次 light 配置，等它稳定再放页面，
    // 否则首帧仍是浅色、随后被刷成深色。启动窗口已是深色底，等待无感。
    setTimeout(() => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'PrismAbility', 'Failed to load Index: %{public}s', JSON.stringify(err));
        }
      });
    }, 320);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'PrismAbility', 'onWindowStageCreate');
    this.setupWindowStage(windowStage);
  }

  /** 迁移到本机时系统走这个回调（而不是 onWindowStageCreate），必须把页面装回来。 */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'PrismAbility', 'onWindowStageRestore');
    this.setupWindowStage(windowStage);
  }

  onBackground(): void {
    // Re-lock hidden folders automatically whenever the app goes to background
    AppStore.getInstance().lockVault();
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow) {
      try {
        this.mainWindow.off('windowSizeChange');
      } catch (_e) {
        // Ignore
      }
      this.mainWindow = null;
    }
  }
}

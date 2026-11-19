import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BreakpointType } from '../common/Constants';
import { ThemeManager } from '../common/ThemeManager';
import { AppStore } from '../services/AppStore';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  private updateBreakpoint(widthPx: number, heightPx: number = 0): void {
    try {
      const d = display.getDefaultDisplaySync();
      const density = d.densityPixels > 0 ? d.densityPixels : 2;
      const widthVp = widthPx / density;
      const heightVp = heightPx > 0 ? (heightPx / density) : 0;
      const isLandscape = heightPx > 0 ? (widthPx > heightPx) : (widthVp >= 600);
      let bp: BreakpointType = 'sm';
      if (widthVp >= 1200) bp = 'xl';
      else if (widthVp >= 840) bp = 'lg';
      else if (widthVp >= 600) bp = 'md';
      AppStorage.setOrCreate('currentBreakpoint', bp);
      AppStorage.setOrCreate('windowWidthVp', Math.round(widthVp));
      AppStorage.setOrCreate('windowHeightVp', Math.round(heightVp));
      AppStorage.setOrCreate('isLandscape', isLandscape);
      AppStore.getInstance().currentBreakpoint = bp;
      AppStore.getInstance().isLandscape = isLandscape;
    } catch (_e) {
      AppStorage.setOrCreate('currentBreakpoint', 'sm');
      AppStorage.setOrCreate('isLandscape', false);
    }
  }

  onBackground(): void {
    // Re-lock hidden folders automatically whenever the app goes to background
    AppStore.getInstance().lockVault();
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'PrismAbility', 'onCreate');
    AppStorage.setOrCreate('currentBreakpoint', 'sm');
    if (want.uri) {
      AppStore.getInstance().handleIncomingFileWant(want.uri);
    }
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want.uri) {
      AppStore.getInstance().handleIncomingFileWant(want.uri);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'PrismAbility', 'onWindowStageCreate');
    ThemeManager.init(this.context.getApplicationContext(), null);

    windowStage.getMainWindow((err, win) => {
      const errCode = err ? err.code : 0;
      if (errCode === 0 && win) {
        this.mainWindow = win;
        ThemeManager.init(this.context.getApplicationContext(), win);
        try {
          const props = win.getWindowProperties();
          this.updateBreakpoint(props.windowRect.width, props.windowRect.height);
          win.on('windowSizeChange', (size) => {
            this.updateBreakpoint(size.width, size.height);
          });
        } catch (_e) {
          // Non-fatal
        }
        // 偏好读取完成前先按当前系统主题着色，避免启动闪底色
        ThemeManager.applyMode(AppStore.getInstance().settings.themeMode);
      }
    });

    AppStore.getInstance().init(this.context).then(() => {
      ThemeManager.applyMode(AppStore.getInstance().settings.themeMode);
    }).catch((e: Error) => {
      hilog.error(DOMAIN, 'PrismAbility', 'AppStore init failed: %{public}s', e.message);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'PrismAbility', 'Failed to load Index: %{public}s', JSON.stringify(err));
      }
    });
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

import { common, Configuration, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeMode } from './Types';

/**
 * 全局主题管理：把用户偏好（跟随系统/浅色/深色）落到 ApplicationContext.setColorMode，
 * 资源限定词（resources/base 与 resources/dark 的 color.json）随之自动刷新全 UI。
 * 窗口底层背景与系统栏颜色在配置变更落地后（EnvironmentCallback）同步。
 */
export class ThemeManager {
  private static appContext: common.ApplicationContext | null = null;
  private static mainWindow: window.Window | null = null;
  /** 当前生效的深浅（显式记录，避免资源管理器与实际模式不一致时恢复错色）；null = 跟随系统且尚未解析 */
  private static effectiveDark: boolean | null = null;

  static init(appContext: common.ApplicationContext, mainWindow: window.Window | null): void {
    ThemeManager.appContext = appContext;
    ThemeManager.mainWindow = mainWindow;
    try {
      const envCallback: EnvironmentCallback = {
        onConfigurationUpdated: (config: Configuration) => {
          hilog.info(0x0001, 'PrismTheme', 'config colorMode=%{public}d', config.colorMode ?? -1);
          ThemeManager.onEffectiveModeChanged(config);
        },
        onMemoryLevel: () => {
        }
      };
      appContext.on('environment', envCallback);
    } catch (_e) {
      // Non-fatal
    }
  }

  static applyMode(mode: ThemeMode): void {
    const colorMode = mode === 'light'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : mode === 'dark'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    try {
      ThemeManager.appContext?.setColorMode(colorMode);
    } catch (_e) {
      // Non-fatal
    }
    if (mode === 'light') {
      ThemeManager.effectiveDark = false;
      ThemeManager.applyChrome(false);
    } else if (mode === 'dark') {
      ThemeManager.effectiveDark = true;
      ThemeManager.applyChrome(true);
    } else {
      // 跟随系统：等待 EnvironmentCallback 带着解析后的 colorMode 回调再上色
      ThemeManager.effectiveDark = null;
      ThemeManager.restoreChrome();
    }
    AppStorage.setOrCreate('themeMode', mode);
  }

  private static onEffectiveModeChanged(config: Configuration): void {
    if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      ThemeManager.effectiveDark = true;
      ThemeManager.applyChrome(true);
    } else if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      ThemeManager.effectiveDark = false;
      ThemeManager.applyChrome(false);
    } else {
      ThemeManager.restoreChrome();
    }
  }

  /** 按当前生效主题恢复窗口与系统栏（播放页退出、系统栏重新启用后调用）。 */
  static restoreChrome(): void {
    ThemeManager.applyChrome(ThemeManager.resolveDark());
  }

  private static resolveDark(): boolean {
    if (ThemeManager.effectiveDark !== null) return ThemeManager.effectiveDark;
    // 跟随系统且回调未到：此时应用模式 == 系统模式，资源解析结果可信
    const rm = ThemeManager.appContext?.resourceManager;
    if (rm) {
      try {
        return ThemeManager.toHex(rm.getColorSync($r('app.color.bg_primary'))) !== '#F1F3F6';
      } catch (_e) {
        // fall through
      }
    }
    return false;
  }

  private static applyChrome(dark: boolean): void {
    const win = ThemeManager.mainWindow;
    if (!win) return;
    const bg = dark ? '#0B0C10' : '#F1F3F6';
    const fg = dark ? '#F3F4F6' : '#16181D';
    try {
      win.setWindowBackgroundColor(bg);
      win.setWindowSystemBarProperties({
        statusBarColor: bg,
        statusBarContentColor: fg,
        navigationBarColor: bg,
        navigationBarContentColor: fg
      }).catch(() => {});
    } catch (_e) {
      // Non-fatal
    }
  }

  /**
   * 播放页沉浸：窗口背景与系统栏内容色钉黑，退出后按当前主题恢复。
   * 解决浅色主题下播放页顶部状态栏/底部导航条区域透出浅色窗口底的问题。
   */
  static setPlayerImmersive(active: boolean): void {
    const win = ThemeManager.mainWindow;
    if (!win) return;
    try {
      if (active) {
        win.setWindowBackgroundColor('#000000');
        win.setWindowSystemBarProperties({
          statusBarColor: '#000000',
          statusBarContentColor: '#FFFFFF',
          navigationBarColor: '#000000',
          navigationBarContentColor: '#FFFFFF'
        }).catch(() => {});
        return;
      }
      ThemeManager.restoreChrome();
    } catch (_e) {
      // Non-fatal
    }
  }

  private static toHex(argb: number): string {
    return '#' + (argb & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase();
  }
}

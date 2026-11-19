import { common, Configuration, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ThemeMode } from './Types';

/**
 * 全局主题管理：把用户偏好（跟随系统/浅色/深色）落到 ApplicationContext.setColorMode，
 * 资源限定词（resources/base 与 resources/dark 的 color.json）随之自动刷新全 UI。
 * 窗口底层背景与系统栏颜色在配置变更落地后（EnvironmentCallback）同步。
 */
export class ThemeManager {
  private static appContext: common.ApplicationContext | null = null;
  private static mainWindow: window.Window | null = null;

  static init(appContext: common.ApplicationContext, mainWindow: window.Window | null): void {
    ThemeManager.appContext = appContext;
    ThemeManager.mainWindow = mainWindow;
    try {
      const envCallback: EnvironmentCallback = {
        onConfigurationUpdated: (config: Configuration) => {
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
      ThemeManager.applyChrome(false);
    } else if (mode === 'dark') {
      ThemeManager.applyChrome(true);
    } else {
      // 跟随系统：等待 EnvironmentCallback 带着解析后的 colorMode 回调再上色
      ThemeManager.syncWindowChromeByResource();
    }
    AppStorage.setOrCreate('themeMode', mode);
  }

  private static onEffectiveModeChanged(config: Configuration): void {
    if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      ThemeManager.applyChrome(true);
    } else if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      ThemeManager.applyChrome(false);
    } else {
      ThemeManager.syncWindowChromeByResource();
    }
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

  /** 无已知生效模式时的兜底：按资源管理器当前解析结果上色（配置稳定时调用）。 */
  private static syncWindowChromeByResource(): void {
    const rm = ThemeManager.appContext?.resourceManager;
    if (!rm) return;
    try {
      const bg = ThemeManager.toHex(rm.getColorSync($r('app.color.bg_primary')));
      ThemeManager.applyChrome(bg !== '#F1F3F6');
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
      ThemeManager.syncWindowChromeByResource();
    } catch (_e) {
      // Non-fatal
    }
  }

  private static toHex(argb: number): string {
    return '#' + (argb & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase();
  }
}

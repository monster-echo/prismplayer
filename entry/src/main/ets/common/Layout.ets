import { BreakpointType } from './Constants';

/**
 * 大屏适配统一尺规。
 *
 * sm  手机竖屏 / 小窗
 * md  平板竖屏、手机横屏（侧栏收成图标轨）
 * lg  平板横屏、PC 窄窗
 * xl  鸿蒙 PC / 2in1 宽窗
 *
 * 页面只从这取内容宽度、留白与分栏数，避免每个页面各写一套 100% 铺满。
 */
export class Layout {
  /** 应用级断点阈值（窗口宽度 vp），与 GridRow 的 12 栅格断点保持一致 */
  static readonly BP_MD: number = 600;
  static readonly BP_LG: number = 840;
  static readonly BP_XL: number = 1440;
  /** 断点滞回带宽：折叠屏在边界反复开合时不抖动 */
  static readonly BP_HYSTERESIS: number = 16;

  static readonly RAIL_WIDTH: number = 76;
  static readonly SIDEBAR_LG: number = 232;
  static readonly SIDEBAR_XL: number = 248;
  static readonly GRID_GAP: number = 14;

  static breakpointFor(widthVp: number): BreakpointType {
    if (widthVp >= Layout.BP_XL) return 'xl';
    if (widthVp >= Layout.BP_LG) return 'lg';
    if (widthVp >= Layout.BP_MD) return 'md';
    return 'sm';
  }

  /**
   * 带滞回的断点解析：宽度落在边界 ±16vp 内时保持当前断点，
   * 避免折叠屏/拖拽窗口在 600 / 840 / 1440 附近来回跳。
   */
  static resolveBreakpoint(widthVp: number, current: BreakpointType): BreakpointType {
    const next = Layout.breakpointFor(widthVp);
    if (next === current) return current;
    const boundary = Math.max(Layout.boundaryOf(current), Layout.boundaryOf(next));
    return Math.abs(widthVp - boundary) < Layout.BP_HYSTERESIS ? current : next;
  }

  private static boundaryOf(bp: BreakpointType): number {
    if (bp === 'xl') return Layout.BP_XL;
    if (bp === 'lg') return Layout.BP_LG;
    if (bp === 'md') return Layout.BP_MD;
    return 0;
  }

  static isWide(bp: BreakpointType): boolean {
    return bp === 'lg' || bp === 'xl';
  }

  static isRail(bp: BreakpointType): boolean {
    return bp === 'md';
  }

  static useSidebar(bp: BreakpointType): boolean {
    return bp !== 'sm';
  }

  static sidebarWidth(bp: BreakpointType, collapsed: boolean): number {
    if (bp === 'xl') return collapsed ? Layout.RAIL_WIDTH : Layout.SIDEBAR_XL;
    if (bp === 'lg') return collapsed ? Layout.RAIL_WIDTH : Layout.SIDEBAR_LG;
    return Layout.RAIL_WIDTH;
  }

  /** 页面左右留白。 */
  static gutter(bp: BreakpointType): number {
    if (bp === 'xl') return 40;
    if (bp === 'lg') return 32;
    if (bp === 'md') return 24;
    return 20;
  }

  /** 影库 / 片源这类内容流的宽度上限，超出后居中留白而不是无限拉宽。 */
  static contentMax(bp: BreakpointType): number {
    if (bp === 'xl') return 1200;
    if (bp === 'lg') return 1060;
    if (bp === 'md') return 880;
    return 620;
  }

  /** 设置、表单、法律文本这类阅读型页面的宽度上限。 */
  static readingMax(bp: BreakpointType): number {
    return bp === 'sm' ? 620 : 760;
  }

  /** 列表行（观看历史、搜索命中）的宽度上限。 */
  static listMax(bp: BreakpointType): number {
    return bp === 'sm' ? 620 : 900;
  }

  /** 详情页宽度上限。 */
  static detailMax(bp: BreakpointType): number {
    if (bp === 'sm') return 620;
    if (bp === 'md') return 880;
    if (bp === 'lg') return 1040;
    return 1120;
  }

  /**
   * 侧栏占用后，页面实际可用的内容宽度。
   * 与页面外层 padding + constraintSize maxWidth 的算法保持一致。
   */
  static contentWidth(windowWidthVp: number, bp: BreakpointType, sidebarWidthVp: number): number {
    const usable = Math.max(280, windowWidthVp - sidebarWidthVp);
    return Math.max(280, Math.min(usable - Layout.gutter(bp) * 2, Layout.contentMax(bp)));
  }

  /** 按最小卡片宽度铺满，避免固定列数在大屏上留下大片空轨道。 */
  static cardColumns(contentWidthVp: number, minCardVp: number, gapVp: number, maxColumns: number): number {
    const usable = Math.max(0, contentWidthVp);
    const columns = Math.floor((usable + gapVp) / (minCardVp + gapVp));
    return Math.max(2, Math.min(maxColumns, columns));
  }

  /** 海报墙列数：大屏给更大的海报，而不是把手机列数横向拉伸。 */

  /** 首页精选横幅高度：随断点放大，但不无限拉伸。 */
  static heroHeight(bp: BreakpointType): number {
    if (bp === 'xl') return 336;
    if (bp === 'lg') return 310;
    if (bp === 'md') return 272;
    return 224;
  }
}

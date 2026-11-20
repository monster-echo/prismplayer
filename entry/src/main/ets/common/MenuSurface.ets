/**
 * 弹层菜单统一表面。
 *
 * 系统 bindMenu 默认浮层在浅色下是纯白、无描边，叠在浅灰页面或白色卡片上会糊成一片；
 * 这里统一给主题化的底色 + 描边。播放页固定在暗色场景，单独用暗色表面，避免浅色主题下
 * 弹出一块刺眼的白板。
 */
export function appMenuOptions(): MenuOptions {
  return {
    backgroundColor: $r('app.color.menu_bg'),
    borderRadius: 14,
    outlineColor: $r('app.color.menu_border'),
    outlineWidth: 1
  };
}

export function playerMenuOptions(): MenuOptions {
  return {
    backgroundColor: '#FF1B1E27',
    borderRadius: 14,
    outlineColor: '#40FFFFFF',
    outlineWidth: 1
  };
}

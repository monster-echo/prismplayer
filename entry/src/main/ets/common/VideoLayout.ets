export interface PictureRect {
  leftVp: number;
  topVp: number;
  widthVp: number;
  heightVp: number;
}

/**
 * Computes the on-screen rectangle of the video picture inside a letterboxed viewport,
 * mirroring XComponent sizing (aspectRatio + constraintSize maxWidth/maxHeight 100%, centered).
 * aspect = undefined means "fill" mode: the picture occupies the whole viewport.
 */
export function computePictureRect(
  viewportWidthVp: number,
  viewportHeightVp: number,
  aspect: number | undefined
): PictureRect {
  const w = viewportWidthVp > 0 ? viewportWidthVp : 360;
  const h = viewportHeightVp > 0 ? viewportHeightVp : 780;
  if (!aspect || aspect <= 0) {
    return { leftVp: 0, topVp: 0, widthVp: w, heightVp: h };
  }
  let widthVp = w;
  let heightVp = w / aspect;
  if (heightVp > h) {
    heightVp = h;
    widthVp = h * aspect;
  }
  return {
    leftVp: (w - widthVp) / 2,
    topVp: (h - heightVp) / 2,
    widthVp,
    heightVp
  };
}

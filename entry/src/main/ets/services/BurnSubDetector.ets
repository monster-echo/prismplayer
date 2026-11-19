import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { textRecognition } from '@kit.CoreVisionKit';
import prismNative from 'libprismplayer.so';

export interface BurnSubMaskResult {
  yTop: number;
  yBottom: number;
}

interface CandidateBand {
  frameIndex: number;
  topRatio: number;
  bottomRatio: number;
  score: number;
}

interface BandCluster {
  tops: number[];
  bottoms: number[];
  frames: Set<number>;
  scoreSum: number;
}

interface FrameScan {
  bands: CandidateBand[];
}

/**
 * Offline burned-in subtitle detector for LOCAL video files.
 * Samples sparse keyframes via AVImageGenerator (never touches the playback pipeline),
 * looks for a temporally stable bright/high-contrast text band in the lower picture area,
 * and optionally confirms marginal hits with on-device OCR (Core Vision Kit, no permission).
 */
export class BurnSubDetector {
  private static readonly SCAN_TOP_RATIO = 0.58;
  private static readonly ANALYSIS_WIDTH = 480;

  static isLocalPlayable(url: string): boolean {
    return url.startsWith('file://') || url.startsWith('content://') || url.startsWith('/');
  }

  /**
   * @param localUrl streamUrl known to be a local file://, content:// or absolute path
   * @param durationMs playback duration when already known (0 = probe the file)
   */
  static async detect(localUrl: string, durationMs: number): Promise<BurnSubMaskResult | null> {
    let fd = -1;
    let generator: media.AVImageGenerator | null = null;
    const frames: image.PixelMap[] = [];
    try {
      const file = fs.openSync(localUrl, fs.OpenMode.READ_ONLY);
      fd = file.fd;
      const stat = fs.statSync(fd);
      if (stat.size <= 0) return null;

      let durMs = durationMs;
      if (durMs <= 0) {
        try {
          const meta = prismNative.probeLocalMedia(fd, 0, stat.size);
          durMs = meta.durationMs;
        } catch (_e) {
          durMs = 0;
        }
      }
      if (durMs <= 0) return null;

      generator = await media.createAVImageGenerator();
      const location: media.AVFileDescriptor = { fd: fd, offset: 0, length: stat.size };
      generator.fdSrc = location;

      const sampleCount = durMs < 90000 ? 10 : 14;
      const scans: FrameScan[] = [];
      let refAspect = 0;
      for (let i = 0; i < sampleCount; i++) {
        const ratio = 0.05 + (0.9 * i) / Math.max(1, sampleCount - 1);
        const timeUs = Math.round(durMs * ratio * 1000);
        let pm: image.PixelMap | null = null;
        try {
          if (refAspect <= 0) {
            // First sample at full resolution to learn the aspect ratio for cheap scaled sampling
            const fullParam: media.PixelMapParams = {};
            pm = await generator.fetchFrameByTime(
              timeUs,
              media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
              fullParam
            );
          } else {
            const scaledParam: media.PixelMapParams = {
              width: BurnSubDetector.ANALYSIS_WIDTH,
              height: Math.round(BurnSubDetector.ANALYSIS_WIDTH / refAspect)
            };
            pm = await generator.fetchFrameByTime(
              timeUs,
              media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
              scaledParam
            );
          }
        } catch (_e) {
          continue;
        }
        if (!pm) continue;
        if (refAspect <= 0) {
          try {
            const first = await pm.getImageInfo();
            if (first.size.width > 0 && first.size.height > 0) {
              refAspect = first.size.width / first.size.height;
            }
          } catch (_e) {
            // Keep full-resolution sampling if image info is unavailable
          }
        }
        frames.push(pm);
        const scan = await BurnSubDetector.scanFrame(pm, scans.length);
        scans.push(scan);
      }

      const result = BurnSubDetector.aggregateBands(scans, frames.length);
      if (!result) {
        return null;
      }

      // Marginal confidence: confirm readable text exists in the band via on-device OCR
      const presentRatio = frames.length > 0 ? result.frames.size / frames.length : 0;
      if (presentRatio < 0.72 && presentRatio >= 0.45) {
        const ocrHits = await BurnSubDetector.ocrConfirmBands(frames, result);
        if (!ocrHits && presentRatio < 0.6) {
          return null;
        }
      }
      if (presentRatio < 0.45) {
        return null;
      }
      return result.mask;
    } catch (_e) {
      return null;
    } finally {
      for (let i = 0; i < frames.length; i++) {
        try {
          await frames[i].release();
        } catch (_e) {
          // Ignore
        }
      }
      if (generator) {
        try {
          await generator.release();
        } catch (_e) {
          // Ignore
        }
      }
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (_e) {
          // Ignore
        }
      }
    }
  }

  /** Detects candidate text bands in the lower part of one frame. */
  private static async scanFrame(pm: image.PixelMap, frameIndex: number): Promise<FrameScan> {
    const empty: FrameScan = { bands: [] };
    try {
      const info = await pm.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (w < 80 || h < 80) return empty;
      const bufSize = pm.getPixelBytesNumber();
      const expected = w * h * 4;
      if (bufSize < expected) return empty;
      const buf = new ArrayBuffer(bufSize);
      await pm.readPixelsToBuffer(buf);
      const px = new Uint8Array(buf);

      const scanStart = Math.floor(h * BurnSubDetector.SCAN_TOP_RATIO);
      const isTextRow: boolean[] = [];
      const rowFrac: number[] = [];
      for (let y = scanStart; y < h; y += 2) {
        let textish = 0;
        let total = 0;
        const rowOff = y * w * 4;
        for (let x = 8; x < w - 8; x += 2) {
          const o = rowOff + x * 4;
          const lum = (px[o] * 77 + px[o + 1] * 150 + px[o + 2] * 29) >> 8;
          const oLeft = rowOff + (x - 6) * 4;
          const lumLeft = (px[oLeft] * 77 + px[oLeft + 1] * 150 + px[oLeft + 2] * 29) >> 8;
          const bright = lum >= 185;
          const contrast = Math.abs(lum - lumLeft) >= 70;
          if (bright || contrast) {
            textish++;
          }
          total++;
        }
        const frac = total > 0 ? textish / total : 0;
        rowFrac.push(frac);
        isTextRow.push(frac >= 0.015 && frac <= 0.8);
      }

      // Cluster consecutive text rows (single-row gaps tolerated) into candidate bands
      const bands: CandidateBand[] = [];
      let runStart = -1;
      let missStreak = 0;
      for (let i = 0; i < isTextRow.length; i++) {
        if (isTextRow[i]) {
          if (runStart < 0) {
            runStart = i;
          }
          missStreak = 0;
        } else if (runStart >= 0) {
          missStreak++;
          if (missStreak > 1) {
            BurnSubDetector.pushBand(bands, frameIndex, runStart, i - missStreak, rowFrac, scanStart, h);
            runStart = -1;
            missStreak = 0;
          }
        }
      }
      if (runStart >= 0) {
        BurnSubDetector.pushBand(bands, frameIndex, runStart, isTextRow.length - 1, rowFrac, scanStart, h);
      }
      return { bands: bands };
    } catch (_e) {
      return empty;
    }
  }

  private static pushBand(
    out: CandidateBand[],
    frameIndex: number,
    startIdx: number,
    endIdx: number,
    rowFrac: number[],
    scanStart: number,
    frameH: number
  ): void {
    const spanRows = endIdx - startIdx + 1;
    if (spanRows < 2) return; // under ~4 px after 2-row stepping: noise
    let fracSum = 0;
    for (let i = startIdx; i <= endIdx; i++) {
      fracSum += rowFrac[i];
    }
    const avgFrac = fracSum / spanRows;
    if (avgFrac > 0.85) return; // solid bright area (sky / letterbox edge), not text
    const topY = scanStart + startIdx * 2;
    const bottomY = scanStart + endIdx * 2;
    const topRatio = topY / frameH;
    const bottomRatio = bottomY / frameH;
    if (bottomRatio - topRatio < 0.012) return;
    out.push({ frameIndex: frameIndex, topRatio: topRatio, bottomRatio: bottomRatio, score: avgFrac });
  }

  /** Groups candidate bands across frames and picks the most persistent bottom cluster. */
  private static aggregateBands(scans: FrameScan[], frameCount: number): BurnSubResultAggregate | null {
    if (frameCount < 3) return null;
    const all: CandidateBand[] = [];
    for (let i = 0; i < scans.length; i++) {
      for (let j = 0; j < scans[i].bands.length; j++) {
        all.push(scans[i].bands[j]);
      }
    }
    if (all.length === 0) return null;
    all.sort((a, b) => (a.topRatio + a.bottomRatio) / 2 - (b.topRatio + b.bottomRatio) / 2);

    const clusters: BandCluster[] = [];
    for (let i = 0; i < all.length; i++) {
      const band = all[i];
      const center = (band.topRatio + band.bottomRatio) / 2;
      let merged = false;
      for (let c = 0; c < clusters.length; c++) {
        const cl = clusters[c];
        const clCenter = BurnSubDetector.clusterCenter(cl);
        const overlap = Math.max(0, Math.min(band.bottomRatio, BurnSubDetector.clusterBottom(cl)) -
          Math.max(band.topRatio, BurnSubDetector.clusterTop(cl)));
        const near = Math.abs(center - clCenter) <= 0.05;
        if (near || overlap > 0.008) {
          cl.tops.push(band.topRatio);
          cl.bottoms.push(band.bottomRatio);
          cl.frames.add(band.frameIndex);
          cl.scoreSum += band.score;
          merged = true;
          break;
        }
      }
      if (!merged) {
        clusters.push({
          tops: [band.topRatio],
          bottoms: [band.bottomRatio],
          frames: new Set<number>([band.frameIndex]),
          scoreSum: band.score
        });
      }
    }

    const minPresent = Math.max(3, Math.ceil(frameCount * 0.45));
    let best: BandCluster | null = null;
    for (let c = 0; c < clusters.length; c++) {
      const cl = clusters[c];
      if (cl.frames.size < minPresent) continue;
      if (!best || cl.frames.size > best.frames.size ||
        (cl.frames.size === best.frames.size && BurnSubDetector.clusterCenter(cl) > BurnSubDetector.clusterCenter(best))) {
        best = cl;
      }
    }
    if (!best) return null;

    const sortedTops = best.tops.slice().sort((a, b) => a - b);
    const sortedBottoms = best.bottoms.slice().sort((a, b) => a - b);
    const medianTop = sortedTops[Math.floor(sortedTops.length / 2)];
    const medianBottom = sortedBottoms[Math.floor(sortedBottoms.length / 2)];

    const margin = 0.014;
    let yTop = Math.max(0, medianTop - margin);
    let yBottom = Math.min(1, medianBottom + margin);
    if (yBottom - yTop < 0.04) {
      const mid = (yTop + yBottom) / 2;
      yTop = Math.max(0, mid - 0.03);
      yBottom = Math.min(1, mid + 0.03);
    }
    return {
      mask: { yTop: yTop, yBottom: yBottom },
      frames: best.frames
    };
  }

  private static clusterCenter(cl: BandCluster): number {
    const centerSum = BurnSubDetector.clusterTop(cl) + BurnSubDetector.clusterBottom(cl);
    return centerSum / 2;
  }

  private static clusterTop(cl: BandCluster): number {
    let sum = 0;
    for (let i = 0; i < cl.tops.length; i++) sum += cl.tops[i];
    return cl.tops.length > 0 ? sum / cl.tops.length : 0;
  }

  private static clusterBottom(cl: BandCluster): number {
    let sum = 0;
    for (let i = 0; i < cl.bottoms.length; i++) sum += cl.bottoms[i];
    return cl.bottoms.length > 0 ? sum / cl.bottoms.length : 1;
  }

  /**
   * Confirms that the detected band actually contains readable text, using the on-device
   * OCR engine. Fully defensive: any failure counts as "not confirmed" without throwing.
   */
  private static async ocrConfirmBands(frames: image.PixelMap[], cluster: BurnSubResultAggregate): Promise<boolean> {
    let hits = 0;
    let attempts = 0;
    for (let i = 0; i < frames.length && attempts < 3; i++) {
      if (!cluster.frames.has(i)) continue;
      attempts++;
      try {
        const visionInfo: textRecognition.VisionInfo = { pixelMap: frames[i] };
        const res = await textRecognition.recognizeText(visionInfo);
        const full = res.value || '';
        if (full.trim().length >= 2) {
          hits++;
        }
      } catch (_e) {
        // OCR unavailable on this device / model not ready: treat as not confirmed
      }
    }
    return hits >= 2;
  }
}

interface BurnSubResultAggregate {
  mask: BurnSubMaskResult;
  frames: Set<number>;
}

import prismNative from 'libprismplayer.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaItem } from '../common/Types';

/** 文件名/片源里能看出来的编码线索 -> mime。 */
interface CodecHint {
  token: string;
  mime: string;
}

const CODEC_HINTS: CodecHint[] = [
  { token: 'x265', mime: 'video/hevc' },
  { token: 'h265', mime: 'video/hevc' },
  { token: 'hevc', mime: 'video/hevc' },
  { token: 'hdr', mime: 'video/hevc' },
  { token: 'x264', mime: 'video/avc' },
  { token: 'h264', mime: 'video/avc' },
  { token: 'avc', mime: 'video/avc' },
  { token: 'av1', mime: 'video/av01' },
  { token: 'vp9', mime: 'video/x-vnd.on2.vp9' }
];

const LOG_TAG: string = 'PrismCodec';

/**
 * 设备硬解能力查询（带进程内缓存）。
 *
 * 只回答「本机有没有这个 mime 的硬件解码器」，不猜封装、不看文件名。
 * 底层是一次 OH_AVCodec_GetCapabilityByCategory(mime, false, HARDWARE)，
 * 查不到能力时返回 false，调用方据此降级到软解。
 */
export class CodecCapability {
  private static cache: Map<string, boolean> = new Map();
  private static names: Map<string, string> = new Map();

  /** 从片名/文件名里猜一个编码 mime；猜不出时返回空串。 */
  static hintMime(item: MediaItem): string {
    const raw = `${item.title || ''} ${item.qualityTag || ''} ${item.fileName || ''} ${item.remotePath || ''} ${item.streamUrl || ''}`.toLowerCase();
    for (let i = 0; i < CODEC_HINTS.length; i++) {
      if (raw.includes(CODEC_HINTS[i].token)) return CODEC_HINTS[i].mime;
    }
    return '';
  }

  static supportsHardware(mime: string): boolean {
    if (!mime) return false;
    const hit = CodecCapability.cache.get(mime);
    if (hit !== undefined) return hit;
    // 默认乐观：只有底层明确回答「没有硬解器」才降级软解。
    // 查询本身报错（老版本 so、权限异常等）时保持硬解，避免一次失败让整机退化为软解。
    let ok = true;
    try {
      const cap = prismNative.queryVideoDecoderCapability(mime);
      ok = cap.supported;
      if (ok && cap.name) CodecCapability.names.set(mime, cap.name);
      hilog.info(0x0001, LOG_TAG, 'capability mime=%{public}s supported=%{public}s name=%{public}s',
        mime, `${ok}`, cap.name || '');
    } catch (e) {
      hilog.warn(0x0001, LOG_TAG, 'capability query failed, assume supported mime=%{public}s msg=%{public}s',
        mime, e instanceof Error ? e.message : String(e));
      ok = true;
    }
    CodecCapability.cache.set(mime, ok);
    return ok;
  }

  /** 设备上实际使用的硬解器名称；没有则空串，可直接展示到技术统计。 */
  static decoderName(mime: string): string {
    if (!mime) return '';
    return CodecCapability.names.get(mime) || '';
  }
}

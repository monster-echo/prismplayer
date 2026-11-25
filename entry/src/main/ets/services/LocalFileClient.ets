import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import prismNative from 'libprismplayer.so';
import { Formatters } from '../common/Formatters';
import { MediaSource, RemoteFileEntry } from '../common/Types';
import { WebDavTestResult } from './WebDavClient';

/**
 * 本机存储的目录访问。
 *
 * 鸿蒙没有「扫一遍全盘」的权限，本机目录来自用户通过 DocumentViewPicker 授权并持久化的
 * directory URI（`file://docs/...`）。注意：fileIo.listFile 只接受应用沙箱路径，直接传 URI
 * 会报 13900002；URI 目录必须先用 fs.open 拿到 fd，再由 native 侧 readdir 枚举。
 * 这里把它包成与 WebDAV / SMB 相同的 listDirectory 契约，片源浏览、扫描、封面提取就都复用了。
 */
export class LocalFileClient {
  static resolveRoot(source: MediaSource): string {
    return source.rootPath || source.baseUrl || '';
  }

  /** 是否是需要走 fd 枚举的授权 URI（沙箱路径才可以直接 listFile）。 */
  static isPickerUri(path: string): boolean {
    return path.startsWith('file://') || path.startsWith('content://') || path.startsWith('datashare://');
  }

  /**
   * 拼接子项路径。URI 目录里的文件名必须百分号编码：Download 下一个以 `#` 开头的文件，
   * 不编码会被当成 URI fragment，stat/open 实际落到父目录，扫描就会把文件当目录无限递套。
   * 沙箱路径不是 URI，保持原样（名字里的 `#`/`%` 就是普通字符）。
   */
  static joinChildPath(parent: string, name: string): string {
    const base = parent.replace(/\/+$/, '');
    const child = LocalFileClient.isPickerUri(parent) ? encodeURIComponent(name) : name;
    return base.length > 0 ? `${base}/${child}` : `/${child}`;
  }

  /** 打开一次并检查是否目录：拿到的 fd 同时验证了授权仍然有效。 */
  static async isDirectory(target: string): Promise<boolean> {
    let fd = -1;
    try {
      const file = await fs.open(target, fs.OpenMode.READ_ONLY);
      fd = file.fd;
      return fs.statSync(fd).isDirectory();
    } catch (_e) {
      return false;
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (_e) {
          // 关闭失败不影响判断结果
        }
      }
    }
  }

  /**
   * 列目录名。URI 目录优先 open + native readdir；失败时再尝试 URI->路径 + listFile，
   * 兼容授权按路径生效的系统版本。沙箱路径直接 listFile。
   */
  static async listNames(target: string): Promise<string[]> {
    if (!target) return [];
    if (!LocalFileClient.isPickerUri(target)) {
      return await fs.listFile(target);
    }

    let lastError = '';
    let fd = -1;
    try {
      const file = await fs.open(target, fs.OpenMode.READ_ONLY);
      fd = file.fd;
      const names = prismNative.listDirectoryFd(fd);
      if (names !== null) {
        hilog.debug(0x0001, 'PrismLocal', 'fd list ok fd=%{public}d count=%{public}d uri=%{public}s',
          fd, names.length, target);
        return names;
      }
      lastError = '目录句柄无法枚举';
      hilog.warn(0x0001, 'PrismLocal', 'fd readdir returned null fd=%{public}d uri=%{public}s', fd, target);
    } catch (e) {
      const err = e as BusinessError;
      lastError = `${err.code} ${err.message}`;
      hilog.warn(0x0001, 'PrismLocal', 'open dir failed code=%{public}d msg=%{public}s uri=%{public}s',
        err.code, err.message, target);
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (_e) {
          // 忽略关闭失败
        }
      }
    }

    try {
      const path = new fileUri.FileUri(target).path;
      if (path && path !== target) {
        const names = await fs.listFile(path);
        hilog.debug(0x0001, 'PrismLocal', 'path list ok count=%{public}d path=%{public}s', names.length, path);
        return names;
      }
    } catch (e) {
      const err = e as BusinessError;
      lastError = `${err.code} ${err.message}`;
      hilog.warn(0x0001, 'PrismLocal', 'path fallback failed code=%{public}d msg=%{public}s uri=%{public}s',
        err.code, err.message, target);
    }
    if (lastError.includes('13900001') || lastError.includes('13900012') ||
      lastError.toLowerCase().includes('permission')) {
      throw new Error('本机文件夹授权已失效，请重新选择文件夹');
    }
    throw new Error(lastError || '目录不可读');
  }

  private static formatDate(mtimeSeconds: number): string {
    if (!mtimeSeconds || mtimeSeconds <= 0) return '';
    const d = new Date(mtimeSeconds * 1000);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  private static contentTypeOf(name: string): string {
    const lower = name.toLowerCase();
    if (Formatters.isVideoFile(lower)) return 'video/*';
    if (Formatters.isAudioFile(lower)) return 'audio/*';
    if (Formatters.isSubtitleFile(lower)) return 'text/plain';
    if (Formatters.isImageFile(lower)) return 'image/*';
    if (lower.endsWith('.nfo') || lower.endsWith('.xml')) return 'text/xml';
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    const root = LocalFileClient.resolveRoot(source);
    if (!root) {
      return { ok: false, latencyMs: 0, entryCount: 0, message: '还没有选择本机文件夹' };
    }
    try {
      const names = await LocalFileClient.listNames(root);
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: names.length,
        message: `本机目录可读 · ${names.length} 项`
      };
    } catch (_e) {
      return {
        ok: false,
        latencyMs: Date.now() - start,
        entryCount: 0,
        message: '授权已失效，请重新选择本机文件夹'
      };
    }
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    const target = dirPath && dirPath !== '/' ? dirPath : LocalFileClient.resolveRoot(source);
    if (!target) return [];

    let names: string[] = [];
    try {
      names = await LocalFileClient.listNames(target);
    } catch (e) {
      throw new Error(`无法读取本机目录：${e instanceof Error ? e.message : String(e)}`);
    }

    const entries: RemoteFileEntry[] = [];
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (name.startsWith('.')) continue;
      const child = LocalFileClient.joinChildPath(target, name);
      let isDirectory = false;
      let size = 0;
      let lastModified = '';
      try {
        const st = await fs.stat(child);
        isDirectory = st.isDirectory();
        size = isDirectory ? 0 : st.size;
        lastModified = LocalFileClient.formatDate(st.mtime);
      } catch (_e) {
        continue;
      }
      entries.push({
        name,
        path: child,
        fullUrl: child,
        isDirectory,
        size,
        lastModified,
        contentType: LocalFileClient.contentTypeOf(name),
        isVideo: !isDirectory && Formatters.isVideoFile(name),
        isSubtitle: !isDirectory && Formatters.isSubtitleFile(name),
        isAudio: !isDirectory && Formatters.isAudioFile(name),
        isImage: !isDirectory && Formatters.isImageFile(name)
      });
    }

    entries.sort((a: RemoteFileEntry, b: RemoteFileEntry) => {
      if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.localeCompare(b.name, 'zh-CN');
    });
    return entries;
  }

  static async readText(path: string): Promise<string> {
    return await fs.readText(path);
  }

  /** 把授权的本机图片复制进缓存目录，返回可直接交给 Image 的沙箱路径。 */
  static async copyInto(srcPath: string, destPath: string): Promise<void> {
    await fs.copyFile(srcPath, destPath);
  }
}

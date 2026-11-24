import { fileIo as fs } from '@kit.CoreFileKit';
import { Formatters } from '../common/Formatters';
import { MediaSource, RemoteFileEntry } from '../common/Types';
import { WebDavTestResult } from './WebDavClient';

/**
 * 本机存储的目录访问。
 *
 * 鸿蒙没有「扫一遍全盘」的权限，本机目录来自用户通过 DocumentViewPicker 授权并持久化的
 * directory URI（`file://docs/...`）。拿到授权后直接走 fileIo 读写即可，无需再经网络层；
 * 这里把它包成与 WebDAV / SMB 相同的 listDirectory 契约，片源浏览、扫描、封面提取就都复用了。
 */
export class LocalFileClient {
  static resolveRoot(source: MediaSource): string {
    return source.rootPath || source.baseUrl || '';
  }

  private static joinPath(parent: string, name: string): string {
    return `${parent.replace(/\/+$/, '')}/${name}`;
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
      const names = await fs.listFile(root);
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
      names = await fs.listFile(target);
    } catch (e) {
      throw new Error(`无法读取本机目录：${e instanceof Error ? e.message : String(e)}`);
    }

    const entries: RemoteFileEntry[] = [];
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (name.startsWith('.')) continue;
      const child = LocalFileClient.joinPath(target, name);
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

import prismNative from 'libprismplayer.so';
import { Formatters } from '../common/Formatters';
import { MediaSource, RemoteFileEntry } from '../common/Types';
import { WebDavTestResult } from './WebDavClient';

export interface ParsedSmbSource {
  host: string;
  port: number;
  share: string;
  relPath: string;
  username: string;
  password: string;
}

export class SmbClient {
  static parseSource(source: MediaSource, overridePath?: string): ParsedSmbSource {
    let rawUrl = source.baseUrl.trim();
    let host = rawUrl;
    let port = 445;
    let urlShare = '';
    let urlSub = '';

    if (rawUrl.toLowerCase().startsWith('smb://')) {
      rawUrl = rawUrl.substring(6);
    } else if (rawUrl.includes('://')) {
      const idx = rawUrl.indexOf('://');
      rawUrl = rawUrl.substring(idx + 3);
    }

    const slashIdx = rawUrl.indexOf('/');
    const authority = slashIdx >= 0 ? rawUrl.substring(0, slashIdx) : rawUrl;
    const afterHost = slashIdx >= 0 ? rawUrl.substring(slashIdx + 1).replace(/\/+$/, '') : '';

    // Strip user@ if present
    const atIdx = authority.lastIndexOf('@');
    const hostPort = atIdx >= 0 ? authority.substring(atIdx + 1) : authority;
    const colonIdx = hostPort.lastIndexOf(':');
    if (colonIdx > 0 && !hostPort.startsWith('[')) {
      host = hostPort.substring(0, colonIdx);
      const parsedPort = parseInt(hostPort.substring(colonIdx + 1), 10);
      if (!isNaN(parsedPort) && parsedPort > 0) port = parsedPort;
    } else {
      host = hostPort.replace(/^\[|\]$/g, '');
    }

    if (afterHost.length > 0) {
      const segSlash = afterHost.indexOf('/');
      if (segSlash >= 0) {
        urlShare = afterHost.substring(0, segSlash);
        urlSub = '/' + afterHost.substring(segSlash + 1);
      } else {
        urlShare = afterHost;
      }
    }

    const chosenPathRaw = (overridePath !== undefined ? overridePath : (source.rootPath || '/')).trim();
    let share = urlShare;
    let relPath = chosenPathRaw || '/';

    if (!share) {
      // Extract share from first segment of rootPath/overridePath e.g. /homes/rw/download/movie
      const clean = chosenPathRaw.replace(/^\/+|\/+$/g, '');
      const firstSlash = clean.indexOf('/');
      if (clean.length > 0) {
        if (firstSlash >= 0) {
          share = clean.substring(0, firstSlash);
          relPath = '/' + clean.substring(firstSlash + 1);
        } else {
          share = clean;
          relPath = '/';
        }
      } else {
        share = 'Public';
        relPath = '/';
      }
    } else {
      if (overridePath === undefined && urlSub && (!chosenPathRaw || chosenPathRaw === '/')) {
        relPath = urlSub;
      }
      if (!relPath.startsWith('/')) relPath = '/' + relPath;
      // Strip duplicated /share prefix if user included it in rootPath
      if (relPath === `/${share}`) {
        relPath = '/';
      } else if (relPath.startsWith(`/${share}/`)) {
        relPath = relPath.substring(share.length + 1);
      }
    }

    return {
      host,
      port,
      share,
      relPath: relPath.replace(/\/{2,}/g, '/') || '/',
      username: source.username.trim(),
      password: source.password
    };
  }

  static buildSmbUrl(cfg: ParsedSmbSource, entryPath: string): string {
    const cleanRel = entryPath.startsWith('/') ? entryPath : `/${entryPath}`;
    return `smb://${cfg.host}:${cfg.port}/${cfg.share}${cleanRel}`;
  }

  static extractRelPathFromUrl(source: MediaSource, urlOrPath: string): string {
    const cfg = SmbClient.parseSource(source);
    if (!urlOrPath.toLowerCase().startsWith('smb://')) {
      return urlOrPath.startsWith('/') ? urlOrPath : `/${urlOrPath}`;
    }
    const prefix = `smb://${cfg.host}:${cfg.port}/${cfg.share}`;
    if (urlOrPath.startsWith(prefix)) {
      const rest = urlOrPath.substring(prefix.length);
      return rest || '/';
    }
    const rest = urlOrPath.substring(6);
    const first = rest.indexOf('/');
    if (first < 0) return '/';
    const afterHost = rest.substring(first + 1);
    const second = afterHost.indexOf('/');
    if (second < 0) return '/';
    return afterHost.substring(second) || '/';
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const parsed = SmbClient.parseSource(source);
    if (!parsed.host) {
      return { ok: false, latencyMs: 0, entryCount: 0, message: '请输入 SMB 服务器 IP 或主机名' };
    }
    try {
      const res = await prismNative.smbTestConnection(
        {
          host: parsed.host,
          port: parsed.port,
          share: parsed.share,
          username: parsed.username,
          password: parsed.password
        },
        parsed.relPath
      );
      return {
        ok: res.ok,
        latencyMs: res.latencyMs,
        entryCount: res.entryCount,
        message: res.message
      };
    } catch (e) {
      return {
        ok: false,
        latencyMs: 0,
        entryCount: 0,
        message: e instanceof Error ? e.message : String(e)
      };
    }
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    const parsed = SmbClient.parseSource(source, dirPath);
    const res = await prismNative.smbListDirectory(
      {
        host: parsed.host,
        port: parsed.port,
        share: parsed.share,
        username: parsed.username,
        password: parsed.password
      },
      parsed.relPath
    );
    if (!res.ok) {
      throw new Error(res.error || 'SMB 目录读取失败');
    }

    const entries: RemoteFileEntry[] = [];
    for (let i = 0; i < res.entries.length; i++) {
      const e = res.entries[i];
      // Preserve UI path scoped nicely so relative navigation works consistently
      const uiPath = parsed.host && source.baseUrl.toLowerCase().includes(`/${parsed.share}`)
        ? e.path
        : `/${parsed.share}${e.path === '/' ? '' : e.path}`;
      const isVid = !e.isDirectory && Formatters.isVideoFile(e.name);
      const isSub = !e.isDirectory && Formatters.isSubtitleFile(e.name);
      entries.push({
        name: e.name,
        path: uiPath,
        fullUrl: SmbClient.buildSmbUrl(parsed, e.path),
        isDirectory: e.isDirectory,
        size: e.size,
        lastModified: e.lastModifiedMs > 0 ? new Date(e.lastModifiedMs).toLocaleDateString() : '',
        contentType: isVid ? 'video/*' : (isSub ? 'text/plain' : 'application/octet-stream'),
        isVideo: isVid,
        isSubtitle: isSub
      });
    }

    entries.sort((a, b) => {
      if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
    return entries;
  }

  /** 读取 SMB 上的二进制小文件（海报等）。 */
  static async fetchBytes(urlOrPath: string, source: MediaSource, maxBytes: number = 16 * 1024 * 1024): Promise<ArrayBuffer> {
    const parsed = SmbClient.parseSource(source);
    const rel = SmbClient.extractRelPathFromUrl(source, urlOrPath);
    return prismNative.smbReadFileBytes(
      {
        host: parsed.host,
        port: parsed.port,
        share: parsed.share,
        username: parsed.username,
        password: parsed.password
      },
      rel,
      maxBytes
    );
  }

  static async fetchText(urlOrPath: string, source: MediaSource): Promise<string> {
    const parsed = SmbClient.parseSource(source);
    const rel = SmbClient.extractRelPathFromUrl(source, urlOrPath);
    return prismNative.smbReadTextFile(
      {
        host: parsed.host,
        port: parsed.port,
        share: parsed.share,
        username: parsed.username,
        password: parsed.password
      },
      rel,
      2 * 1024 * 1024
    );
  }
}

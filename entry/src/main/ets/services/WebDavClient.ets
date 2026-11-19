import { rcp } from '@kit.RemoteCommunicationKit';
import { Formatters } from '../common/Formatters';
import { MediaSource, RemoteFileEntry } from '../common/Types';

export interface WebDavTestResult {
  ok: boolean;
  latencyMs: number;
  entryCount: number;
  message: string;
}

export interface HttpsRangeResponse {
  statusCode: number;
  totalSize: number;
  contentType: string;
  redirectUrl: string;
  data: ArrayBuffer;
}

const PROPFIND_BODY =
  '<?xml version="1.0" encoding="utf-8" ?>' +
  '<D:propfind xmlns:D="DAV:">' +
  '<D:prop>' +
  '<D:displayname/>' +
  '<D:getcontentlength/>' +
  '<D:getlastmodified/>' +
  '<D:getcontenttype/>' +
  '<D:resourcetype/>' +
  '</D:prop>' +
  '</D:propfind>';

export class WebDavClient {
  private static session: rcp.Session | null = null;

  private static getSession(): rcp.Session {
    if (!WebDavClient.session) {
      WebDavClient.session = rcp.createSession();
    }
    return WebDavClient.session;
  }

  static normalizeBaseUrl(baseUrl: string): string {
    return baseUrl.trim().replace(/\/+$/, '');
  }

  static normalizeDirPath(path: string): string {
    let p = path.trim();
    if (!p.startsWith('/')) p = '/' + p;
    if (!p.endsWith('/')) p += '/';
    return p.replace(/\/{2,}/g, '/');
  }

  static buildTargetUrl(baseUrl: string, dirPath: string): string {
    const cleanBase = WebDavClient.normalizeBaseUrl(baseUrl);
    const cleanPath = WebDavClient.normalizeDirPath(dirPath);
    const encodedSegments = cleanPath
      .split('/')
      .map((seg, idx) => (idx === 0 || seg === '' ? '' : encodeURIComponent(seg)))
      .join('/');
    return `${cleanBase}${encodedSegments}`;
  }

  static encodePathSegmentsPreservingPct(rawPath: string): string {
    return rawPath
      .split('/')
      .map((seg) => {
        if (!seg) return '';
        try {
          // Decode once then re-encode so we handle both encoded and unencoded spaces/Chinese/brackets
          return encodeURIComponent(decodeURIComponent(seg));
        } catch (_e) {
          return encodeURIComponent(seg);
        }
      })
      .join('/');
  }

  static joinRemoteFileUrl(baseUrl: string, hrefOrPath: string): string {
    if (hrefOrPath.startsWith('http://') || hrefOrPath.startsWith('https://')) {
      const mFull = hrefOrPath.match(/^(https?:\/\/[^/]+)(.*)$/i);
      if (mFull) {
        return `${mFull[1]}${WebDavClient.encodePathSegmentsPreservingPct(mFull[2] || '/')}`;
      }
      return hrefOrPath;
    }
    const cleanBase = WebDavClient.normalizeBaseUrl(baseUrl);
    const m = cleanBase.match(/^(https?:\/\/[^/]+)(.*)$/i);
    const origin = m ? m[1] : cleanBase;
    if (hrefOrPath.startsWith('/')) {
      return `${origin}${WebDavClient.encodePathSegmentsPreservingPct(hrefOrPath)}`;
    }
    return `${cleanBase}/${WebDavClient.encodePathSegmentsPreservingPct(hrefOrPath)}`;
  }

  private static extractXmlBlocks(xml: string, localTag: string): string[] {
    const regex = new RegExp(`<(?:[\\w-]+:)?${localTag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/(?:[\\w-]+:)?${localTag}>`, 'gi');
    const out: string[] = [];
    let match: RegExpExecArray | null = regex.exec(xml);
    while (match !== null) {
      out.push(match[1]);
      match = regex.exec(xml);
    }
    return out;
  }

  private static extractFirstTagText(xml: string, localTag: string): string {
    const regex = new RegExp(`<(?:[\\w-]+:)?${localTag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/(?:[\\w-]+:)?${localTag}>`, 'i');
    const m = xml.match(regex);
    if (!m || !m[1]) return '';
    return m[1]
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .trim();
  }

  private static hasCollectionTag(xml: string): boolean {
    return /<(?:[\w-]+:)?collection(?:\s*\/|\s*>)/i.test(xml);
  }

  private static extractPathFromHref(href: string): string {
    let p = href.trim();
    const schemeIdx = p.indexOf('://');
    if (schemeIdx > 0) {
      const slashIdx = p.indexOf('/', schemeIdx + 3);
      p = slashIdx >= 0 ? p.substring(slashIdx) : '/';
    }
    try {
      return decodeURIComponent(p);
    } catch (_e) {
      return p;
    }
  }

  static parsePropfindXml(xml: string, baseUrl: string, currentDirPath: string): RemoteFileEntry[] {
    const responses = WebDavClient.extractXmlBlocks(xml, 'response');
    const normCurrent = WebDavClient.normalizeDirPath(currentDirPath);
    const baseMatch = WebDavClient.normalizeBaseUrl(baseUrl).match(/^https?:\/\/[^/]+(.*)$/i);
    const baseSubPath = baseMatch && baseMatch[1] ? baseMatch[1] : '';
    const expectedSelfPath = WebDavClient.normalizeDirPath(`${baseSubPath}${normCurrent}`);

    const entries: RemoteFileEntry[] = [];
    for (let i = 0; i < responses.length; i++) {
      const block = responses[i];
      const rawHref = WebDavClient.extractFirstTagText(block, 'href');
      if (!rawHref) continue;

      const decodedPath = WebDavClient.extractPathFromHref(rawHref);
      const normDecodedDir = decodedPath.endsWith('/') ? decodedPath : `${decodedPath}/`;
      // Skip the directory itself (first response in standard WebDAV PROPFIND Depth: 1)
      if (normDecodedDir === expectedSelfPath || normDecodedDir === normCurrent) {
        continue;
      }

      const isDirectory = WebDavClient.hasCollectionTag(block) || rawHref.endsWith('/');
      let name = WebDavClient.extractFirstTagText(block, 'displayname');
      if (!name) {
        const trimmed = decodedPath.replace(/\/+$/, '');
        const lastSlash = trimmed.lastIndexOf('/');
        name = lastSlash >= 0 ? trimmed.substring(lastSlash + 1) : trimmed;
      }
      if (!name || name === '.' || name === '..') continue;

      const sizeStr = WebDavClient.extractFirstTagText(block, 'getcontentlength');
      const size = sizeStr ? (parseInt(sizeStr, 10) || 0) : 0;
      const lastModified = WebDavClient.extractFirstTagText(block, 'getlastmodified');
      const contentType = WebDavClient.extractFirstTagText(block, 'getcontenttype');

      let relativePath = decodedPath;
      if (baseSubPath && relativePath.startsWith(baseSubPath)) {
        relativePath = relativePath.substring(baseSubPath.length);
      }
      if (!relativePath.startsWith('/')) {
        relativePath = '/' + relativePath;
      }

      const fullUrl = WebDavClient.joinRemoteFileUrl(baseUrl, rawHref);
      entries.push({
        name,
        path: relativePath,
        fullUrl,
        isDirectory,
        size,
        lastModified,
        contentType,
        isVideo: !isDirectory && Formatters.isVideoFile(name),
        isSubtitle: !isDirectory && Formatters.isSubtitleFile(name)
      });
    }

    entries.sort((a, b) => {
      if (a.isDirectory !== b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });
    return entries;
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    const targetUrl = WebDavClient.buildTargetUrl(source.baseUrl, dirPath);
    const headers: rcp.RequestHeaders = {
      'depth': '1',
      'content-type': 'application/xml; charset=utf-8',
      'user-agent': 'PrismPlayer/1.0'
    };
    const auth = Formatters.buildBasicAuthHeader(source.username, source.password);
    if (auth) {
      headers['authorization'] = auth;
    }

    const req = new rcp.Request(targetUrl, 'PROPFIND', headers, PROPFIND_BODY);
    req.configuration = {
      security: {
        remoteValidation: source.allowInsecureTls ? 'skip' : 'system'
      },
      transfer: {
        timeout: {
          connectMs: 8000,
          transferMs: 12000
        }
      }
    };

    let resp = await WebDavClient.getSession().fetch(req);
    if (resp.statusCode === 400) {
      // Retry once with a fresh session in case an upstream WebDAV server left keep-alive body bytes unconsumed.
      try {
        WebDavClient.session?.close();
      } catch (_e) {
      }
      WebDavClient.session = null;
      const retryReq = new rcp.Request(targetUrl, 'PROPFIND', headers, PROPFIND_BODY);
      retryReq.configuration = req.configuration;
      resp = await WebDavClient.getSession().fetch(retryReq);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`WebDAV HTTP ${resp.statusCode}`);
    }
    const xml = resp.toString() || '';
    return WebDavClient.parsePropfindXml(xml, source.baseUrl, dirPath);
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const entries = await WebDavClient.listDirectory(source, source.rootPath || '/');
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: entries.length,
        message: `连接成功 (${entries.length} 项)`
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return {
        ok: false,
        latencyMs: Date.now() - start,
        entryCount: 0,
        message: Formatters.toFriendlyError(msg)
      };
    }
  }

  static async fetchText(url: string, source?: MediaSource): Promise<string> {
    const headers: rcp.RequestHeaders = {
      'user-agent': 'PrismPlayer/1.0'
    };
    if (source) {
      const auth = Formatters.buildBasicAuthHeader(source.username, source.password);
      if (auth) {
        headers['authorization'] = auth;
      }
    }
    const req = new rcp.Request(url, 'GET', headers);
    req.configuration = {
      security: {
        remoteValidation: source && source.allowInsecureTls ? 'skip' : 'system'
      },
      transfer: {
        timeout: {
          connectMs: 8000,
          transferMs: 10000
        }
      }
    };
    const resp = await WebDavClient.getSession().fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(`HTTP ${resp.statusCode}`);
    }
    return resp.toString() || '';
  }

  static async fetchRangeChunkForNative(
    url: string,
    authHeader: string,
    rangeStart: number,
    rangeEnd: number,
    allowInsecure: boolean
  ): Promise<HttpsRangeResponse> {
    const isDouyinStream = url.includes('snssdk.com') || url.includes('douyin') || url.includes('zjcdn.com') || url.includes('amemv.com');
    const headers: rcp.RequestHeaders = {
      'user-agent': isDouyinStream
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1'
        : 'PrismPlayer/1.0'
    };
    if (isDouyinStream) {
      headers['referer'] = 'https://www.douyin.com/';
    }
    if (authHeader) {
      headers['authorization'] = authHeader;
    }
    if (rangeStart >= 0 && rangeEnd >= rangeStart) {
      headers['range'] = `bytes=${rangeStart}-${rangeEnd}`;
    }

    const req = new rcp.Request(url, 'GET', headers);
    req.configuration = {
      security: {
        remoteValidation: allowInsecure ? 'skip' : 'system'
      },
      transfer: {
        timeout: {
          connectMs: 8000,
          transferMs: 14000
        }
      }
    };

    try {
      const resp = await WebDavClient.getSession().fetch(req);
      let totalSize = -1;
      const contentRangeHeader = resp.headers['content-range'];
      if (typeof contentRangeHeader === 'string') {
        const slash = contentRangeHeader.lastIndexOf('/');
        if (slash >= 0) {
          const totalStr = contentRangeHeader.substring(slash + 1).trim();
          if (totalStr !== '*') {
            totalSize = parseInt(totalStr, 10) || -1;
          }
        }
      }
      if (totalSize <= 0 && resp.statusCode === 200) {
        const lenHeader = resp.headers['content-length'];
        if (typeof lenHeader === 'string') {
          totalSize = parseInt(lenHeader, 10) || -1;
        }
      }
      const ctypeRaw = resp.headers['content-type'];
      const contentType = typeof ctypeRaw === 'string' ? ctypeRaw : 'application/octet-stream';
      const redirectUrl = resp.effectiveUrl ? resp.effectiveUrl.toString() : '';

      return {
        statusCode: resp.statusCode,
        totalSize,
        contentType,
        redirectUrl,
        data: resp.body ? resp.body : new ArrayBuffer(0)
      };
    } catch (_e) {
      return {
        statusCode: 0,
        totalSize: -1,
        contentType: 'application/octet-stream',
        redirectUrl: '',
        data: new ArrayBuffer(0)
      };
    }
  }
}

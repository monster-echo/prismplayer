import { Formatters } from '../common/Formatters';
import { MediaSource, RemoteFileEntry, parseSourceExtra } from '../common/Types';
import { HttpHelper } from './HttpHelper';
import { WebDavTestResult } from './WebDavClient';

const EMPTY_SHA256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

const SHA256_K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

export interface ParsedS3Endpoint {
  scheme: string;
  hostHeader: string;
  endpointOrigin: string;
  bucket: string;
  basePrefix: string;
  region: string;
  usePathStyle: boolean;
}

interface AmzDateStamp {
  amzDate: string;
  dateStamp: string;
}

export class S3Client {
  private static utf8Encode(str: string): Uint8Array {
    const bytes: number[] = [];
    for (let i = 0; i < str.length; i++) {
      let code = str.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < str.length) {
        const next = str.charCodeAt(++i);
        const cp = 0x10000 + (((code - 0xd800) << 10) | (next - 0xdc00));
        bytes.push(
          0xf0 | (cp >> 18),
          0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f),
          0x80 | (cp & 0x3f)
        );
      } else {
        bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      }
    }
    return new Uint8Array(bytes);
  }

  private static rotr(n: number, bits: number): number {
    return (n >>> bits) | (n << (32 - bits));
  }

  static sha256Bytes(data: Uint8Array): Uint8Array {
    const bitLen = data.length * 8;
    const padLen = ((56 - ((data.length + 1) % 64)) + 64) % 64;
    const totalLen = data.length + 1 + padLen + 8;
    const buf = new Uint8Array(totalLen);
    buf.set(data, 0);
    buf[data.length] = 0x80;
    const view = new DataView(buf.buffer);
    view.setUint32(totalLen - 8, Math.floor(bitLen / 0x100000000), false);
    view.setUint32(totalLen - 4, bitLen >>> 0, false);

    let h0 = 0x6a09e667;
    let h1 = 0xbb67ae85;
    let h2 = 0x3c6ef372;
    let h3 = 0xa54ff53a;
    let h4 = 0x510e527f;
    let h5 = 0x9b05688c;
    let h6 = 0x1f83d9ab;
    let h7 = 0x5be0cd19;

    const w = new Int32Array(64);
    for (let offset = 0; offset < totalLen; offset += 64) {
      for (let i = 0; i < 16; i++) {
        w[i] = view.getInt32(offset + i * 4, false);
      }
      for (let i = 16; i < 64; i++) {
        const s0 = S3Client.rotr(w[i - 15], 7) ^ S3Client.rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        const s1 = S3Client.rotr(w[i - 2], 17) ^ S3Client.rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }

      let a = h0;
      let b = h1;
      let c = h2;
      let d = h3;
      let e = h4;
      let f = h5;
      let g = h6;
      let h = h7;

      for (let i = 0; i < 64; i++) {
        const S1 = S3Client.rotr(e, 6) ^ S3Client.rotr(e, 11) ^ S3Client.rotr(e, 25);
        const ch = (e & f) ^ (~e & g);
        const temp1 = (h + S1 + ch + SHA256_K[i] + w[i]) | 0;
        const S0 = S3Client.rotr(a, 2) ^ S3Client.rotr(a, 13) ^ S3Client.rotr(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = (S0 + maj) | 0;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) | 0;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) | 0;
      }

      h0 = (h0 + a) | 0;
      h1 = (h1 + b) | 0;
      h2 = (h2 + c) | 0;
      h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0;
      h5 = (h5 + f) | 0;
      h6 = (h6 + g) | 0;
      h7 = (h7 + h) | 0;
    }

    const out = new Uint8Array(32);
    const outView = new DataView(out.buffer);
    outView.setInt32(0, h0, false);
    outView.setInt32(4, h1, false);
    outView.setInt32(8, h2, false);
    outView.setInt32(12, h3, false);
    outView.setInt32(16, h4, false);
    outView.setInt32(20, h5, false);
    outView.setInt32(24, h6, false);
    outView.setInt32(28, h7, false);
    return out;
  }

  static toHex(bytes: Uint8Array): string {
    let s = '';
    for (let i = 0; i < bytes.length; i++) {
      const v = bytes[i];
      s += ((v >> 4) & 0x0f).toString(16) + (v & 0x0f).toString(16);
    }
    return s;
  }

  static sha256Hex(text: string): string {
    return S3Client.toHex(S3Client.sha256Bytes(S3Client.utf8Encode(text)));
  }

  static hmacSha256(key: Uint8Array, msg: string): Uint8Array {
    let k = key;
    if (k.length > 64) {
      k = S3Client.sha256Bytes(k);
    }
    const oPad = new Uint8Array(64);
    const iPad = new Uint8Array(64);
    for (let i = 0; i < 64; i++) {
      const kb = i < k.length ? k[i] : 0;
      oPad[i] = kb ^ 0x5c;
      iPad[i] = kb ^ 0x36;
    }
    const msgBytes = S3Client.utf8Encode(msg);
    const inner = new Uint8Array(64 + msgBytes.length);
    inner.set(iPad, 0);
    inner.set(msgBytes, 64);
    const innerHash = S3Client.sha256Bytes(inner);

    const outer = new Uint8Array(64 + 32);
    outer.set(oPad, 0);
    outer.set(innerHash, 64);
    return S3Client.sha256Bytes(outer);
  }

  static inferRegionFromHost(host: string): string {
    const h = host.toLowerCase();
    if (h.includes('.r2.cloudflarestorage.com')) return 'auto';
    const awsMatch = h.match(/(?:^|\.)s3[.-]([a-z0-9-]+)\.amazonaws\.com/);
    if (awsMatch) return awsMatch[1];
    const ossMatch = h.match(/oss-([a-z0-9-]+)\.aliyuncs\.com/);
    if (ossMatch) return ossMatch[1];
    const cosMatch = h.match(/cos\.([a-z0-9-]+)\.myqcloud\.com/);
    if (cosMatch) return cosMatch[1];
    return 'us-east-1';
  }

  static parseEndpoint(source: MediaSource): ParsedS3Endpoint {
    const extra = parseSourceExtra(source.extraConfig);
    let raw = (source.baseUrl || '').trim().replace(/\/+$/, '');
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = `https://${raw}`;
    }
    const m = raw.match(/^(https?):\/\/([^/]+)(\/.*)?$/i);
    const scheme = m ? m[1].toLowerCase() : 'https';
    const hostHeader = m ? m[2] : raw;
    const rawPath = m && m[3] ? m[3].replace(/^\/+|\/+$/g, '') : '';

    let bucket = '';
    let basePrefix = '';
    let usePathStyle = extra.usePathStyle !== undefined ? extra.usePathStyle : true;

    if (rawPath) {
      const firstSlash = rawPath.indexOf('/');
      if (firstSlash >= 0) {
        bucket = rawPath.substring(0, firstSlash);
        basePrefix = rawPath.substring(firstSlash + 1);
      } else {
        bucket = rawPath;
      }
      usePathStyle = true;
    } else if (extra.usePathStyle === false) {
      usePathStyle = false;
    }

    const region = (extra.region || '').trim() || S3Client.inferRegionFromHost(hostHeader);
    return {
      scheme,
      hostHeader,
      endpointOrigin: `${scheme}://${hostHeader}`,
      bucket,
      basePrefix,
      region,
      usePathStyle
    };
  }

  static awsUriEncode(input: string, encodeSlash: boolean): string {
    let out = '';
    const bytes = S3Client.utf8Encode(input);
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i];
      const ch = String.fromCharCode(b);
      if (
        (b >= 0x41 && b <= 0x5a) ||
        (b >= 0x61 && b <= 0x7a) ||
        (b >= 0x30 && b <= 0x39) ||
        ch === '_' || ch === '-' || ch === '~' || ch === '.'
      ) {
        out += ch;
      } else if (ch === '/' && !encodeSlash) {
        out += '/';
      } else {
        out += '%' + b.toString(16).toUpperCase().padStart(2, '0');
      }
    }
    return out;
  }

  private static formatAmzDate(date: Date): AmzDateStamp {
    const y = date.getUTCFullYear().toString().padStart(4, '0');
    const m = (date.getUTCMonth() + 1).toString().padStart(2, '0');
    const d = date.getUTCDate().toString().padStart(2, '0');
    const hh = date.getUTCHours().toString().padStart(2, '0');
    const mm = date.getUTCMinutes().toString().padStart(2, '0');
    const ss = date.getUTCSeconds().toString().padStart(2, '0');
    const dateStamp = `${y}${m}${d}`;
    return {
      amzDate: `${dateStamp}T${hh}${mm}${ss}Z`,
      dateStamp
    };
  }

  private static deriveSigningKey(secretKey: string, dateStamp: string, region: string): Uint8Array {
    const kDate = S3Client.hmacSha256(S3Client.utf8Encode(`AWS4${secretKey}`), dateStamp);
    const kRegion = S3Client.hmacSha256(kDate, region);
    const kService = S3Client.hmacSha256(kRegion, 's3');
    return S3Client.hmacSha256(kService, 'aws4_request');
  }

  static buildCanonicalObjectPath(ep: ParsedS3Endpoint, objectKey: string): string {
    const cleanKey = objectKey.replace(/^\/+/, '');
    if (ep.bucket && ep.usePathStyle) {
      return cleanKey
        ? `/${S3Client.awsUriEncode(ep.bucket, true)}/${S3Client.awsUriEncode(cleanKey, false)}`
        : `/${S3Client.awsUriEncode(ep.bucket, true)}`;
    }
    return cleanKey ? `/${S3Client.awsUriEncode(cleanKey, false)}` : '/';
  }

  /** Builds a 12-hour AWS SigV4 Presigned GET URL compatible with Range seeking & subtitles. */
  static buildPresignedGetUrl(
    source: MediaSource,
    objectKey: string,
    expiresSec: number = 43200,
    nowDate?: Date
  ): string {
    const ep = S3Client.parseEndpoint(source);
    const canonicalUri = S3Client.buildCanonicalObjectPath(ep, objectKey);
    if (!source.username || !source.password) {
      return `${ep.endpointOrigin}${canonicalUri}`;
    }

    const stamp = S3Client.formatAmzDate(nowDate || new Date());
    const amzDate = stamp.amzDate;
    const dateStamp = stamp.dateStamp;
    const scope = `${dateStamp}/${ep.region}/s3/aws4_request`;
    const queryPairs: Array<[string, string]> = [
      ['X-Amz-Algorithm', 'AWS4-HMAC-SHA256'],
      ['X-Amz-Credential', `${source.username}/${scope}`],
      ['X-Amz-Date', amzDate],
      ['X-Amz-Expires', `${expiresSec}`],
      ['X-Amz-SignedHeaders', 'host']
    ];
    queryPairs.sort((a, b) => (a[0] < b[0] ? -1 : (a[0] > b[0] ? 1 : 0)));
    const canonicalQuery = queryPairs
      .map(p => `${S3Client.awsUriEncode(p[0], true)}=${S3Client.awsUriEncode(p[1], true)}`)
      .join('&');

    const canonicalRequest = [
      'GET',
      canonicalUri,
      canonicalQuery,
      `host:${ep.hostHeader.toLowerCase()}`,
      '',
      'host',
      'UNSIGNED-PAYLOAD'
    ].join('\n');

    const stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      S3Client.sha256Hex(canonicalRequest)
    ].join('\n');

    const signingKey = S3Client.deriveSigningKey(source.password, dateStamp, ep.region);
    const signature = S3Client.toHex(S3Client.hmacSha256(signingKey, stringToSign));
    return `${ep.endpointOrigin}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
  }

  private static async signedListObjectsXml(
    source: MediaSource,
    prefix: string,
    maxKeys: number
  ): Promise<string> {
    const ep = S3Client.parseEndpoint(source);
    const canonicalUri = S3Client.buildCanonicalObjectPath(ep, '');
    const queryPairs: Array<[string, string]> = [
      ['delimiter', '/'],
      ['list-type', '2'],
      ['max-keys', `${maxKeys}`]
    ];
    if (prefix) {
      queryPairs.push(['prefix', prefix]);
    }
    queryPairs.sort((a, b) => (a[0] < b[0] ? -1 : (a[0] > b[0] ? 1 : 0)));
    const canonicalQuery = queryPairs
      .map(p => `${S3Client.awsUriEncode(p[0], true)}=${S3Client.awsUriEncode(p[1], true)}`)
      .join('&');

    const url = `${ep.endpointOrigin}${canonicalUri}?${canonicalQuery}`;
    if (!source.username || !source.password) {
      const resp = await HttpHelper.requestText(url, {
        allowInsecureTls: source.allowInsecureTls,
        timeoutMs: 10000
      });
      if (resp.statusCode >= 400) {
        throw new Error(`HTTP ${resp.statusCode}：S3 存储桶访问失败`);
      }
      return resp.body;
    }

    const stamp = S3Client.formatAmzDate(new Date());
    const amzDate = stamp.amzDate;
    const dateStamp = stamp.dateStamp;
    const scope = `${dateStamp}/${ep.region}/s3/aws4_request`;
    const canonicalHeaders = [
      `host:${ep.hostHeader.toLowerCase()}`,
      `x-amz-content-sha256:${EMPTY_SHA256}`,
      `x-amz-date:${amzDate}`
    ].join('\n');
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    const canonicalRequest = [
      'GET',
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      '',
      signedHeaders,
      EMPTY_SHA256
    ].join('\n');

    const stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      S3Client.sha256Hex(canonicalRequest)
    ].join('\n');
    const signingKey = S3Client.deriveSigningKey(source.password, dateStamp, ep.region);
    const signature = S3Client.toHex(S3Client.hmacSha256(signingKey, stringToSign));
    const authHeader =
      `AWS4-HMAC-SHA256 Credential=${source.username}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

    const resp = await HttpHelper.requestText(url, {
      allowInsecureTls: source.allowInsecureTls,
      timeoutMs: 10000,
      headers: {
        'Authorization': authHeader,
        'x-amz-content-sha256': EMPTY_SHA256,
        'x-amz-date': amzDate
      }
    });
    if (resp.statusCode === 401 || resp.statusCode === 403) {
      throw new Error(`HTTP ${resp.statusCode}：S3 SignatureDoesNotMatch / AccessDenied`);
    }
    if (resp.statusCode >= 400) {
      throw new Error(`HTTP ${resp.statusCode}：S3 列表查询失败`);
    }
    return resp.body;
  }

  private static extractXmlTag(block: string, tag: string): string {
    const m = block.match(new RegExp(`<${tag}>([\\s\\S]*?)<\\/${tag}>`));
    return m ? m[1]
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .trim() : '';
  }

  static parseListObjectsXml(xml: string, currentPrefix: string): RemoteFileEntry[] {
    const entries: RemoteFileEntry[] = [];
    const prefixBlocks = xml.match(/<CommonPrefixes>[\s\S]*?<\/CommonPrefixes>/g) || [];
    for (let i = 0; i < prefixBlocks.length; i++) {
      const p = S3Client.extractXmlTag(prefixBlocks[i], 'Prefix');
      if (!p || p === currentPrefix) continue;
      const trimmed = p.replace(/\/+$/, '');
      const slash = trimmed.lastIndexOf('/');
      const name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
      entries.push({
        name: name || trimmed,
        path: `/${p.replace(/^\/+/, '')}`,
        fullUrl: `s3:///${p.replace(/^\/+/, '')}`,
        isDirectory: true,
        size: 0,
        lastModified: '',
        contentType: 'inode/directory',
        isVideo: false,
        isSubtitle: false
      });
    }

    const contentBlocks = xml.match(/<Contents>[\s\S]*?<\/Contents>/g) || [];
    for (let i = 0; i < contentBlocks.length; i++) {
      const blk = contentBlocks[i];
      const key = S3Client.extractXmlTag(blk, 'Key');
      if (!key || key === currentPrefix || key.endsWith('/')) continue;
      const size = parseInt(S3Client.extractXmlTag(blk, 'Size') || '0', 10) || 0;
      const modified = S3Client.extractXmlTag(blk, 'LastModified');
      const slash = key.lastIndexOf('/');
      const name = slash >= 0 ? key.substring(slash + 1) : key;
      entries.push({
        name,
        path: `/${key.replace(/^\/+/, '')}`,
        fullUrl: `s3:///${key.replace(/^\/+/, '')}`,
        isDirectory: false,
        size,
        lastModified: modified,
        contentType: 'application/octet-stream',
        isVideo: Formatters.isVideoFile(name),
        isSubtitle: Formatters.isSubtitleFile(name)
      });
    }

    entries.sort((a, b) => {
      if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
    return entries;
  }

  private static normalizePrefix(ep: ParsedS3Endpoint, dirPath: string): string {
    let p = (dirPath || '/').trim().replace(/^\/+/, '');
    if (p && !p.endsWith('/')) p += '/';
    if (!p && ep.basePrefix) {
      p = ep.basePrefix.replace(/^\/+/, '');
      if (p && !p.endsWith('/')) p += '/';
    }
    return p;
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const ep = S3Client.parseEndpoint(source);
      const prefix = S3Client.normalizePrefix(ep, source.rootPath || '/');
      const xml = await S3Client.signedListObjectsXml(source, prefix, 15);
      const list = S3Client.parseListObjectsXml(xml, prefix);
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: list.length,
        message: `S3 连接成功 (${ep.region}) · 发现 ${list.length} 项`
      };
    } catch (e) {
      return {
        ok: false,
        latencyMs: Date.now() - start,
        entryCount: 0,
        message: Formatters.toFriendlyError(e instanceof Error ? e.message : String(e))
      };
    }
  }

  static async listDirectory(source: MediaSource, dirPath: string): Promise<RemoteFileEntry[]> {
    const ep = S3Client.parseEndpoint(source);
    const prefix = S3Client.normalizePrefix(ep, dirPath);
    const xml = await S3Client.signedListObjectsXml(source, prefix, 500);
    return S3Client.parseListObjectsXml(xml, prefix);
  }

  static resolvePlayUrl(streamUrlOrKey: string, source: MediaSource): string {
    if (streamUrlOrKey.startsWith('http://') || streamUrlOrKey.startsWith('https://')) {
      return streamUrlOrKey;
    }
    const key = streamUrlOrKey.replace(/^s3:\/\/\/?/, '').replace(/^\/+/, '');
    return S3Client.buildPresignedGetUrl(source, key, 43200);
  }

  static async fetchText(urlOrKey: string, source: MediaSource): Promise<string> {
    const signed = S3Client.resolvePlayUrl(urlOrKey, source);
    const resp = await HttpHelper.requestText(signed, {
      allowInsecureTls: source.allowInsecureTls,
      timeoutMs: 10000
    });
    if (resp.statusCode >= 400) {
      throw new Error(`HTTP ${resp.statusCode}`);
    }
    return resp.body;
  }
}

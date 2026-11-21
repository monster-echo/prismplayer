import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { Formatters } from '../common/Formatters';
import { MediaItem, MediaSource, RemoteFileEntry, parseSourceExtra } from '../common/Types';
import { HttpHelper, HttpTextResponse } from './HttpHelper';
import { WebDavTestResult } from './WebDavClient';

export interface DouyinShareCaption {
  author: string;
  title: string;
  shareUrl: string;
}

export interface DouyinVideoInfo {
  awemeId: string;
  title: string;
  author: string;
  coverUrl: string;
  playUrl: string;
  durationMs: number;
  shareUrl: string;
}

export interface LocalVideoSaveResult {
  ok: boolean;
  localPath: string;
  fileSize: number;
  exportedUri: string;
  message: string;
  /** 沙箱内已落盘离线副本；false 表示本次没有写入离线影库 */
  offline: boolean;
}

export interface LocalVideoSaveOptions {
  /** 下载完成后再调系统文件选择器另存一份 */
  exportToSystemPicker?: boolean;
  /** 决定扩展名的片源文件名（如 xxx.mkv） */
  fileNameHint?: string;
  /** 已接收字节数，节流后回调 */
  onProgress?: (receivedBytes: number) => void;
}

interface DouyinUrlListWrap {
  uri?: string;
  url_list?: string[];
}

interface DouyinVideoObj {
  play_addr?: DouyinUrlListWrap;
  cover?: DouyinUrlListWrap;
  origin_cover?: DouyinUrlListWrap;
  duration?: number;
}

interface DouyinAuthorObj {
  nickname?: string;
}

interface DouyinAwemeItem {
  aweme_id?: string;
  desc?: string;
  author?: DouyinAuthorObj;
  video?: DouyinVideoObj;
}

interface DouyinVideoInfoRes {
  item_list?: DouyinAwemeItem[];
}

interface DouyinRouterPage {
  itemId?: string;
  videoInfoRes?: DouyinVideoInfoRes;
}

interface DouyinRouterLoaderData {
  video_page?: DouyinRouterPage;
  note_page?: DouyinRouterPage;
}

interface DouyinRouterData {
  loaderData?: DouyinRouterLoaderData;
}

interface HybridApiVideoData {
  nwm_video_url_HQ?: string;
  nwm_video_url?: string;
  wm_video_url?: string;
}

interface HybridCoverData {
  cover?: DouyinUrlListWrap;
}

interface HybridApiData {
  aweme_id?: string;
  desc?: string;
  video_data?: HybridApiVideoData;
  author?: DouyinAuthorObj;
  cover_data?: HybridCoverData;
}

interface HybridApiRoot {
  code?: number;
  data?: HybridApiData;
}

export class DouyinClient {
  static readonly MOBILE_UA =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

  private static readonly DEFAULT_TTWID_COOKIE =
    'ttwid=1%7C0dnaOXA3AeOTOwckZDvt2Y2invtHK0cItKlUIjG9Wck%7C1795049712%7Cb6cf34aed94ec5d7ecd907d7fd4bc4a13fa68a650f32ab2fa87b762d4deb8c9b';

  private static dlSession: rcp.Session | null = null;

  /** 本地/导出拷贝的分块大小 */
  private static readonly COPY_CHUNK_BYTES = 4 * 1024 * 1024;

  private static getDownloadSession(): rcp.Session {
    if (!DouyinClient.dlSession) {
      DouyinClient.dlSession = rcp.createSession();
    }
    return DouyinClient.dlSession;
  }

  private static emptyHttpResp(): HttpTextResponse {
    return { statusCode: 500, body: '' };
  }

  /** Extracts the URL and caption from a raw Douyin share text copied from the Douyin app. */
  static parseShareText(rawText: string): DouyinShareCaption {
    const clean = (rawText || '').trim();
    const urlMatch = clean.match(/https?:\/\/[^\s"'<>，。！？、）)】]+/i);
    const shareUrl = urlMatch ? urlMatch[0].replace(/[.,;!?)]+$/, '') : clean;

    let author = '抖音创作者';
    const bracketMatch = clean.match(/看看【([^】]+)】/);
    if (bracketMatch && bracketMatch[1]) {
      author = bracketMatch[1].replace(/的作品$/, '').trim() || author;
    }

    let title = '';
    if (bracketMatch && bracketMatch.index !== undefined) {
      const afterBracket = clean.substring(bracketMatch.index + bracketMatch[0].length);
      const urlIdx = afterBracket.indexOf('http');
      title = (urlIdx >= 0 ? afterBracket.substring(0, urlIdx) : afterBracket).trim();
    } else if (urlMatch && urlMatch.index !== undefined && urlMatch.index > 0) {
      const beforeUrl = clean.substring(0, urlMatch.index)
        .replace(/^\d+\.\d+\s+(?:[:A-Za-z0-9@/.]+\s+)+/, '')
        .replace(/^\d+\.\d+\s*[A-Za-z@/:.]*\s*/, '')
        .replace(/复制打开抖音[，,\s]*/, '')
        .trim();
      title = beforeUrl;
    }

    if (!title) {
      const id = DouyinClient.extractAwemeId(clean);
      title = id ? `抖音短视频_${id.substring(Math.max(0, id.length - 6))}` : '抖音精彩短视频';
    }

    return {
      author,
      title,
      shareUrl
    };
  }

  static extractAwemeId(textOrUrl: string): string {
    const clean = (textOrUrl || '').trim();
    const mVideo = clean.match(/\/(?:video|note)\/(\d{15,21})/);
    if (mVideo) return mVideo[1];
    const mModal = clean.match(/(?:modal_id|item_ids|aweme_id)=(\d{15,21})/);
    if (mModal) return mModal[1];
    const mJson = clean.match(/"(?:itemId|lastPath|aweme_id)"\s*:\s*"(\d{15,21})"/);
    if (mJson) return mJson[1];
    if (/^\d{15,21}$/.test(clean)) return clean;
    return '';
  }

  /** Converts a watermarked Douyin playwm URL to a 1080p watermark-free play URL. */
  static toWatermarkFreeUrl(rawUrl: string): string {
    if (!rawUrl) return '';
    let u = rawUrl.trim().replace(/^http:\/\//i, 'https://');
    if (u.includes('/playwm/')) {
      u = u.replace('/playwm/', '/play/');
    }
    if (u.includes('aweme/v1/play') && !u.includes('ratio=')) {
      const sep = u.includes('?') ? '&' : '?';
      u = `${u}${sep}ratio=1080p&line=0`;
    }
    return u;
  }

  /** Parses SSR window._ROUTER_DATA HTML from iesdouyin.com / m.douyin.com share page. */
  static parseRouterDataHtml(html: string, fallbackCaption?: DouyinShareCaption): DouyinVideoInfo | null {
    const m = html.match(/window\._ROUTER_DATA\s*=\s*(\{[\s\S]+?\})\s*<\/script>/);
    if (!m) return null;
    try {
      const normalizedJson = m[1]
        .replace(/"video_\(id\)\/page"/g, '"video_page"')
        .replace(/"note_\(id\)\/page"/g, '"note_page"');
      const data = JSON.parse(normalizedJson) as DouyinRouterData;
      const loader = data.loaderData;
      const page = loader ? (loader.video_page || loader.note_page) : undefined;
      if (!page) return null;
      const itemList = page.videoInfoRes?.item_list;
      if (!itemList || itemList.length === 0) {
        return null;
      }
      const item = itemList[0];
      const awemeId = item.aweme_id || page.itemId || '';
      const rawPlayList = item.video?.play_addr?.url_list;
      let playUrl = rawPlayList && rawPlayList.length > 0 ? DouyinClient.toWatermarkFreeUrl(rawPlayList[0]) : '';
      if (!playUrl && item.video?.play_addr?.uri) {
        playUrl = `https://aweme.snssdk.com/aweme/v1/play/?video_id=${encodeURIComponent(item.video.play_addr.uri)}&ratio=1080p&line=0`;
      }
      if (!playUrl) return null;

      const covers = item.video?.cover?.url_list || item.video?.origin_cover?.url_list;
      const coverUrl = covers && covers.length > 0 ? covers[0] : '';

      return {
        awemeId: awemeId || `${Date.now()}`,
        title: item.desc || fallbackCaption?.title || `抖音视频 ${awemeId}`,
        author: item.author?.nickname || fallbackCaption?.author || '抖音创作者',
        coverUrl,
        playUrl,
        durationMs: item.video?.duration || 0,
        shareUrl: fallbackCaption?.shareUrl || `https://www.iesdouyin.com/share/video/${awemeId}/`
      };
    } catch (_e) {
      return null;
    }
  }

  static async resolveShareLink(rawInput: string, source?: MediaSource): Promise<DouyinVideoInfo> {
    const caption = DouyinClient.parseShareText(rawInput || (source ? source.baseUrl : ''));
    const shareUrl = caption.shareUrl;
    if (!shareUrl) {
      throw new Error('未识别到有效的抖音分享链接，请粘贴包含 v.douyin.com 或 douyin.com 的分享文本');
    }

    // 1. 分享文本里本身就是视频直链时，不需要解析抖音页面
    const lowerUrl = shareUrl.toLowerCase();
    if (Formatters.isVideoFile(lowerUrl.split('?')[0])) {
      return {
        awemeId: `direct_${Date.now()}`,
        title: caption.title || '视频',
        author: caption.author,
        coverUrl: '',
        playUrl: shareUrl,
        durationMs: 0,
        shareUrl
      };
    }

    // 2. Custom Hybrid Parser API (e.g. Evil0ctal Douyin_TikTok_Download_API) if configured in extraConfig.mirrorUrl
    const extra = parseSourceExtra(source?.extraConfig);
    const apiBase = (extra.mirrorUrl || '').trim().replace(/\/+$/, '');
    const insecure = source ? source.allowInsecureTls : true;
    if (apiBase) {
      const apiUrl = `${apiBase}/api/hybrid/video_data?url=${encodeURIComponent(shareUrl)}&minimal=false`;
      const apiResp = await HttpHelper.requestText(apiUrl, {
        allowInsecureTls: insecure,
        timeoutMs: 12000
      }).catch(() => DouyinClient.emptyHttpResp());
      if (apiResp.statusCode === 200 && apiResp.body.includes('"')) {
        try {
          const root = JSON.parse(apiResp.body) as HybridApiRoot;
          const vd = root.data?.video_data;
          const play = vd?.nwm_video_url_HQ || vd?.nwm_video_url || vd?.wm_video_url || '';
          if (play) {
            const covers = root.data?.cover_data?.cover?.url_list;
            return {
              awemeId: root.data?.aweme_id || `${Date.now()}`,
              title: root.data?.desc || caption.title,
              author: root.data?.author?.nickname || caption.author,
              coverUrl: covers && covers.length > 0 ? covers[0] : '',
              playUrl: DouyinClient.toWatermarkFreeUrl(play),
              durationMs: 0,
              shareUrl
            };
          }
        } catch (_e) {
          // Continue to direct SSR resolution
        }
      }
    }

    // 3. Direct Mobile Share Page SSR Resolution (v.douyin.com -> iesdouyin.com/share/video/{id}/)
    const headers: Record<string, string> = {
      'User-Agent': DouyinClient.MOBILE_UA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cookie': extra.cookie || DouyinClient.DEFAULT_TTWID_COOKIE
    };

    let awemeId = DouyinClient.extractAwemeId(shareUrl);
    for (let attempt = 0; attempt < 2; attempt++) {
      const resp = await HttpHelper.requestText(shareUrl, {
        allowInsecureTls: insecure,
        timeoutMs: 10000,
        headers
      }).catch(() => DouyinClient.emptyHttpResp());

      const parsed = DouyinClient.parseRouterDataHtml(resp.body, caption);
      if (parsed) {
        return parsed;
      }
      if (!awemeId) {
        awemeId = DouyinClient.extractAwemeId(resp.body);
      }
    }

    if (awemeId) {
      const iesUrl = `https://www.iesdouyin.com/share/video/${awemeId}/`;
      const iesResp = await HttpHelper.requestText(iesUrl, {
        allowInsecureTls: insecure,
        timeoutMs: 10000,
        headers
      }).catch(() => DouyinClient.emptyHttpResp());
      const parsedIes = DouyinClient.parseRouterDataHtml(iesResp.body, caption);
      if (parsedIes) {
        return parsedIes;
      }
    }

    throw new Error('抖音分享链接需要验证或已过期，请在抖音内重新复制完整分享文本，或在片源高级设置填入自建 Douyin 解析 API 地址。');
  }

  static async testConnection(source: MediaSource): Promise<WebDavTestResult> {
    const start = Date.now();
    try {
      const info = await DouyinClient.resolveShareLink(source.baseUrl, source);
      return {
        ok: true,
        latencyMs: Date.now() - start,
        entryCount: 1,
        message: `抖音解析成功 · @${info.author}《${info.title.substring(0, 18)}》`
      };
    } catch (e) {
      return {
        ok: false,
        latencyMs: Date.now() - start,
        entryCount: 0,
        message: e instanceof Error ? e.message : String(e)
      };
    }
  }

  static async listDirectory(source: MediaSource, _dirPath: string): Promise<RemoteFileEntry[]> {
    const info = await DouyinClient.resolveShareLink(source.baseUrl, source);
    return [{
      name: `${info.title}.mp4`,
      path: `/douyin/${info.awemeId}.mp4`,
      fullUrl: info.playUrl,
      isDirectory: false,
      size: 0,
      lastModified: `@${info.author} · 无水印原画`,
      contentType: 'video/mp4',
      isVideo: true,
      isSubtitle: false
    }];
  }

  static async scanLibraryItems(source: MediaSource): Promise<MediaItem[]> {
    const info = await DouyinClient.resolveShareLink(source.baseUrl, source);
    return [DouyinClient.toMediaItem(info, source.id)];
  }

  static toMediaItem(info: DouyinVideoInfo, sourceId: string = 'douyin_share'): MediaItem {
    return {
      id: `${sourceId}_dy_${info.awemeId}`,
      sourceId,
      sourceType: 'douyin',
      remotePath: `/douyin/${info.awemeId}.mp4`,
      streamUrl: info.playUrl,
      fileName: `${info.title}.mp4`,
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: `${sourceId}_dy_${info.awemeId}`,
      seriesTitle: `@${info.author}`,
      seasonNo: 1,
      episodeNo: 0,
      title: info.title,
      originalTitle: `@${info.author}`,
      year: new Date().getFullYear(),
      overview: `抖音创作者：@${info.author}\n原始分享链接：${info.shareUrl}`,
      posterUrl: info.coverUrl || 'local://poster_bbb',
      backdropUrl: info.coverUrl || 'local://backdrop_bbb',
      rating: 9.0,
      qualityTag: '抖音无水印',
      tmdbId: 0,
      durationMs: info.durationMs,
      subtitleUrl: '',
      addedAt: Date.now()
    };
  }

  private static sanitizeFileName(raw: string): string {
    const clean = raw
      .replace(/[\\/:*?"<>|#\r\n]+/g, '_')
      .replace(/\s+/g, '_')
      .replace(/^_+|_+$/g, '')
      .substring(0, 64);
    return clean || `video_${Date.now()}`;
  }

  /**
   * Streams a video (Douyin / S3 / HTTP / WebDAV / SMB proxy) into app sandbox storage so it can be
   * watched offline, and optionally exports a copy through the system file picker.
   *
   * The response body is written to disk chunk by chunk. Buffering it with `fetch()` stalls on
   * multi-hundred-MB videos and blows the heap on multi-GB ones.
   */
  static async saveVideoToLocal(
    streamUrl: string,
    title: string,
    context: common.UIAbilityContext,
    options?: LocalVideoSaveOptions
  ): Promise<LocalVideoSaveResult> {
    const opts: LocalVideoSaveOptions = options ?? {};
    try {
      const dirPath = `${context.filesDir}/saved_videos`;
      if (!fs.accessSync(dirPath)) {
        fs.mkdirSync(dirPath);
      }
      const hint = opts.fileNameHint || title || 'video';
      const fileName = `${DouyinClient.sanitizeFileName(Formatters.stripExtension(title || hint))}.${DouyinClient.videoExtension(hint)}`;
      const localPath = `${dirPath}/${fileName}`;

      if (DouyinClient.isLocalUri(streamUrl)) {
        const srcPath = DouyinClient.localFilePath(streamUrl);
        if (srcPath !== localPath) {
          DouyinClient.copyLocalFile(srcPath, localPath);
        }
      } else {
        await DouyinClient.streamDownloadToFile(streamUrl, localPath, opts.onProgress);
      }

      const size = fs.statSync(localPath).size;
      if (size <= 0) {
        throw new Error('保存的文件为空');
      }

      let exportedUri = '';
      let exportNote = '';
      if (opts.exportToSystemPicker === true) {
        try {
          exportedUri = await DouyinClient.exportToSystemPicker(context, localPath, fileName);
        } catch (e) {
          exportNote = ' · 导出失败';
          hilog.error(0x0001, 'PrismSave', 'export failed: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
      }

      hilog.info(0x0001, 'PrismSave', 'save done bytes=%{public}d export=%{public}s',
        size, exportedUri ? 'yes' : 'no');
      const sizeText = Formatters.formatBytes(size);
      return {
        ok: true,
        localPath,
        fileSize: size,
        exportedUri,
        message: exportedUri ? `已保存并导出 (${sizeText})` : `已保存到离线影库 (${sizeText})${exportNote}`,
        offline: true
      };
    } catch (e) {
      const err = e as Error;
      let detail = err && err.message ? err.message : String(e);
      const biz = e as BusinessError;
      if (biz && biz.code > 0) {
        detail = `${detail} [${biz.code}]`;
      }
      hilog.error(0x0001, 'PrismSave', 'save failed: %{public}s', detail);
      return {
        ok: false,
        localPath: '',
        fileSize: 0,
        exportedUri: '',
        message: `保存失败：${detail}`,
        offline: false
      };
    }
  }

  private static isLocalUri(url: string): boolean {
    return url.startsWith('/') || url.startsWith('file://') ||
      url.startsWith('content://') || url.startsWith('datashare://');
  }

  /** file:///a/b 转成沙箱路径 /a/b；其余 URI 原样返回 */
  private static localFilePath(url: string): string {
    return url.startsWith('file:///') ? url.substring('file://'.length) : url;
  }

  private static videoExtension(hint: string): string {
    const clean = (hint || '').split('?')[0].toLowerCase();
    const dot = clean.lastIndexOf('.');
    if (dot >= 0 && dot < clean.length - 1) {
      const ext = clean.substring(dot + 1);
      if (['mp4', 'mkv', 'mov', 'm4v', 'avi', 'ts', 'm2ts', 'webm', 'flv', 'wmv', 'mpg', 'mpeg'].indexOf(ext) >= 0) {
        return ext;
      }
    }
    return 'mp4';
  }

  private static resetDownloadSession(): void {
    if (DouyinClient.dlSession) {
      try {
        DouyinClient.dlSession.close();
      } catch (_e) {
        // Ignore
      }
      DouyinClient.dlSession = null;
    }
  }

  /** 边收边写盘；先写 .part，成功后原子替换目标文件。返回落盘字节数。 */
  private static async streamDownloadToFile(
    url: string,
    localPath: string,
    onProgress?: (receivedBytes: number) => void
  ): Promise<number> {
    const tempPath = `${localPath}.${Date.now()}.part`;
    let outFile: fs.File | null = null;
    let received = 0;
    let lastNotifyAt = 0;
    let writeFailure = '';
    try {
      outFile = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const outFd = outFile.fd;
      const req = new rcp.Request(url, 'GET');
      req.headers = {
        'User-Agent': DouyinClient.MOBILE_UA,
        'Referer': 'https://www.douyin.com/'
      };
      req.configuration = {
        security: { remoteValidation: 'skip' },
        // 大文件下载不设总时长瓶颈，只在 60s 没有新数据时判定卡死
        transfer: {
          timeout: { connectMs: 15000, transferMs: 2 * 60 * 60 * 1000, inactivityMs: 60000 }
        }
      };
      req.destination = (chunk: ArrayBuffer) => {
        if (writeFailure) return;
        try {
          DouyinClient.writeChunk(outFd, chunk);
          received += chunk.byteLength;
          const now = Date.now();
          if (onProgress && now - lastNotifyAt >= 500) {
            lastNotifyAt = now;
            onProgress(received);
          }
        } catch (e) {
          writeFailure = e instanceof Error ? e.message : String(e);
          throw new Error(writeFailure);
        }
      };
      const resp = await DouyinClient.getDownloadSession().fetch(req);
      if (resp.statusCode >= 400) {
        throw new Error(`下载失败 (HTTP ${resp.statusCode})`);
      }
      if (writeFailure) {
        throw new Error(`写入失败：${writeFailure}`);
      }
      if (received <= 0) {
        throw new Error('服务器未返回视频数据');
      }
      try {
        fs.closeSync(outFile);
      } finally {
        outFile = null;
      }
      DouyinClient.replaceFile(tempPath, localPath);
      if (onProgress) {
        onProgress(received);
      }
      return received;
    } catch (e) {
      DouyinClient.resetDownloadSession();
      try {
        fs.unlinkSync(tempPath);
      } catch (_e) {
        // Ignore
      }
      throw e as Error;
    } finally {
      if (outFile) {
        try {
          fs.closeSync(outFile);
        } catch (_e) {
          // Ignore
        }
      }
    }
  }

  /** 用临时文件替换目标；失败时不破坏已有目标文件。 */
  private static replaceFile(tempPath: string, targetPath: string): void {
    try {
      fs.renameSync(tempPath, targetPath);
    } catch (_e) {
      try {
        fs.unlinkSync(targetPath);
      } catch (_e2) {
        // Ignore
      }
      fs.renameSync(tempPath, targetPath);
    }
  }

  private static writeChunk(fd: number, chunk: ArrayBuffer): void {
    let offset = 0;
    while (offset < chunk.byteLength) {
      const part = offset === 0 ? chunk : chunk.slice(offset);
      const written = fs.writeSync(fd, part, { length: chunk.byteLength - offset });
      if (written <= 0) {
        throw new Error('磁盘写入失败');
      }
      offset += written;
    }
  }

  private static copyFdChunked(srcFd: number, destFd: number): number {
    const buf = new ArrayBuffer(DouyinClient.COPY_CHUNK_BYTES);
    let total = 0;
    while (true) {
      const read = fs.readSync(srcFd, buf);
      if (read <= 0) {
        break;
      }
      DouyinClient.writeChunk(destFd, read === buf.byteLength ? buf : buf.slice(0, read));
      total += read;
    }
    return total;
  }

  private static copyLocalFile(srcPath: string, destPath: string): void {
    const tempPath = `${destPath}.${Date.now()}.part`;
    const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
    try {
      const dest = fs.openSync(tempPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        DouyinClient.copyFdChunked(src.fd, dest.fd);
      } finally {
        try {
          fs.closeSync(dest.fd);
        } catch (_e) {
          // Ignore
        }
      }
      DouyinClient.replaceFile(tempPath, destPath);
    } catch (e) {
      try {
        fs.unlinkSync(tempPath);
      } catch (_e) {
        // Ignore
      }
      throw e as Error;
    } finally {
      try {
        fs.closeSync(src.fd);
      } catch (_e) {
        // Ignore
      }
    }
  }

  private static async exportToSystemPicker(
    context: common.UIAbilityContext,
    localPath: string,
    fileName: string
  ): Promise<string> {
    hilog.info(0x0001, 'PrismSave', 'picker open name=%{public}s', fileName);
    const docPicker = new picker.DocumentViewPicker(context);
    const saveOpts = new picker.DocumentSaveOptions();
    saveOpts.newFileNames = [fileName];
    const uris = await docPicker.save(saveOpts);
    hilog.info(0x0001, 'PrismSave', 'picker result count=%{public}d', uris ? uris.length : -1);
    if (!uris || uris.length === 0 || !uris[0]) {
      return '';
    }
    const destUri = uris[0];
    const src = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
    let copyError: Error | null = null;
    try {
      const dest = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        DouyinClient.copyFdChunked(src.fd, dest.fd);
      } catch (e) {
        copyError = e as Error;
      } finally {
        try {
          fs.closeSync(dest.fd);
        } catch (_e) {
          // Ignore
        }
      }
    } finally {
      try {
        fs.closeSync(src.fd);
      } catch (_e) {
        // Ignore
      }
    }
    if (copyError) {
      try {
        fs.unlinkSync(destUri);
      } catch (_e) {
        // Ignore
      }
      throw copyError;
    }
    return destUri;
  }
}

import { textToSpeech } from '@kit.CoreSpeechKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';
import { Formatters } from '../common/Formatters';

export interface OnlineSubtitleResult {
  id: string;
  title: string;
  language: string;
  langLabel: string;
  format: string;
  downloadUrl: string;
  sourceName: string;
}

interface ScoredSubtitle {
  result: OnlineSubtitleResult;
  score: number;
}

interface SubdlSubtitleEntry {
  release_name?: string;
  name?: string;
  lang?: string;
  url?: string;
  subtitlePage?: string;
}

interface SubdlApiResp {
  status?: boolean;
  subtitles?: SubdlSubtitleEntry[];
}

interface OpenSubtitlesFile {
  file_id?: number;
  file_name?: string;
}

interface OpenSubtitlesEntryAttrs {
  subtitle_id?: string;
  release?: string;
  title?: string;
  language?: string;
  ai_translated?: boolean;
  files?: OpenSubtitlesFile[];
}

interface OpenSubtitlesSearchEntry {
  type?: string;
  id?: string;
  attributes?: OpenSubtitlesEntryAttrs;
}

interface OpenSubtitlesSearchResp {
  data?: OpenSubtitlesSearchEntry[];
}

interface OpenSubtitlesDownloadResp {
  link?: string;
  remaining?: number;
}

export class SubtitleService {
  private static session: rcp.Session | null = null;
  private static translationCache: Map<string, string> = new Map<string, string>();
  private static ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private static ttsCreating: boolean = false;
  private static lastSpokenText: string = '';

  private static getSession(): rcp.Session {
    if (!SubtitleService.session) {
      SubtitleService.session = rcp.createSession();
    }
    return SubtitleService.session;
  }

  /**
   * 强大字幕匹配入口：聚合 SubDL（国际）与字幕库（中文）两个来源，
   * 结合视频文件名做季集感知评分排序，返回去重后的候选列表。
   */
  static async searchAllSubtitles(
    query: string,
    videoFileName: string = '',
    langFilter: string = 'all',
    subdlApiKey: string = ''
  ): Promise<OnlineSubtitleResult[]> {
    const cleanQ = (query || '').trim();
    if (!cleanQ) return [];
    const merged: OnlineSubtitleResult[] = [];
    const subdl = await SubtitleService.searchSubdl(cleanQ, langFilter, subdlApiKey).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'subdl error %{public}s', e.message);
      return [] as OnlineSubtitleResult[];
    });
    for (let i = 0; i < subdl.length; i++) merged.push(subdl[i]);
    const osResults = await SubtitleService.searchOpenSubtitlesProvider(cleanQ, langFilter).catch(() => [] as OnlineSubtitleResult[]);
    for (let i = 0; i < osResults.length; i++) merged.push(osResults[i]);
    const zimuku = await SubtitleService.searchZimuku(cleanQ).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'zimuku error %{public}s', e.message);
      return [] as OnlineSubtitleResult[];
    });
    for (let i = 0; i < zimuku.length; i++) merged.push(zimuku[i]);
    hilog.info(0x0001, 'PrismSub', 'searchAll q=%{public}s subdl=%{public}d os=%{public}d zimuku=%{public}d', cleanQ, subdl.length, osResults.length, zimuku.length);
    return SubtitleService.rankSubtitleResults(merged, videoFileName, cleanQ);
  }

  /** 兼容旧调用方：等价于 searchAllSubtitles。 */
  static async searchOnlineSubtitles(query: string, langFilter: string = 'all'): Promise<OnlineSubtitleResult[]> {
    return SubtitleService.searchAllSubtitles(query, '', langFilter);
  }

  private static async searchSubdl(query: string, langFilter: string, apiKey: string = ''): Promise<OnlineSubtitleResult[]> {
    const results: OnlineSubtitleResult[] = [];
    const langParam = langFilter !== 'all' ? `&languages=${encodeURIComponent(langFilter.toUpperCase())}` : '';
    // 用户在设置中自定义的 Key 优先；未配置时使用内置凭据（应用内不展示）
    const effectiveKey = apiKey.trim() || AppConstants.SUBDL_API_KEY;
    const keyParam = `&api_key=${encodeURIComponent(effectiveKey)}`;
    const subdlUrl = `https://api.subdl.com/api/v1/subtitles?film_name=${encodeURIComponent(query)}${langParam}${keyParam}&subs_per_page=12`;
    const req = new rcp.Request(subdlUrl, 'GET', {
      'User-Agent': 'PrismPlayer/1.0',
      'Accept': 'application/json'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 6000, transferMs: 10000 } }
    };
    const resp = await SubtitleService.getSession().fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return results;
    }
    const parsed = JSON.parse(resp.toString() || '{}') as SubdlApiResp;
    const list = parsed.subtitles || [];
    for (let i = 0; i < list.length && results.length < 12; i++) {
      const s = list[i];
      const rawUrl = s.url || '';
      if (!rawUrl) continue;
      const dlUrl = rawUrl.startsWith('http') ? rawUrl : `https://dl.subdl.com${rawUrl.startsWith('/') ? '' : '/'}${rawUrl}`;
      const name = s.release_name || s.name || query;
      const detected = Formatters.detectSubtitleLanguage(s.lang || name, i);
      results.push({
        id: `subdl_${i}_${dlUrl}`,
        title: name,
        language: detected.lang,
        langLabel: detected.label,
        format: name.toLowerCase().includes('.ass') ? 'ASS' : 'SRT',
        downloadUrl: dlUrl,
        sourceName: 'SubDL'
      });
    }
    return results;
  }

  /**
   * OpenSubtitles 官方源：全球最大的多语言字幕库，query 走英文片名效果最佳。
   * Key 无效/限流时返回 "You cannot consume this service"，静默跳过该源。
   */
  private static async searchOpenSubtitlesProvider(query: string, langFilter: string): Promise<OnlineSubtitleResult[]> {
    const results: OnlineSubtitleResult[] = [];
    const langParam = langFilter !== 'all' ? `&languages=${encodeURIComponent(langFilter)}` : '';
    const url = `https://api.opensubtitles.com/api/v1/subtitles?query=${encodeURIComponent(query)}${langParam}&page_size=10`;
    const req = new rcp.Request(url, 'GET', {
      'Api-Key': AppConstants.OPENSUBTITLES_API_KEY,
      'Authorization': `Bearer ${AppConstants.OPENSUBTITLES_USER_TOKEN}`,
      'User-Agent': 'PrismPlayer v1.0',
      'Accept': 'application/json'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 6000, transferMs: 10000 } }
    };
    const resp = await SubtitleService.getSession().fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return results;
    }
    const body = resp.toString() || '';
    if (body.includes('You cannot consume this service')) {
      return results;
    }
    const parsed = JSON.parse(body) as OpenSubtitlesSearchResp;
    const list = parsed.data || [];
    for (let i = 0; i < list.length && results.length < 10; i++) {
      const entry = list[i];
      const attrs = entry.attributes;
      if (!attrs || attrs.ai_translated) continue;
      const files = attrs.files || [];
      const fileId = files.length > 0 ? `${files[0].file_id}` : '';
      if (!fileId) continue;
      const releaseName = attrs.release || attrs.title || query;
      const detected = Formatters.detectSubtitleLanguage(`${releaseName} ${attrs.language || ''}`, results.length);
      const ext = (files[0].file_name || releaseName || '').toLowerCase();
      results.push({
        id: `os_${attrs.subtitle_id || fileId}`,
        title: releaseName,
        language: detected.lang,
        langLabel: detected.label,
        format: ext.includes('.ass') ? 'ASS' : 'SRT',
        downloadUrl: `osdl://download?file_id=${fileId}`,
        sourceName: 'OpenSubtitles'
      });
    }
    return results;
  }

  /**
   * 字幕库（zimuku）中文源：搜索页 HTML 解析出详情链接（直链下载需两跳，在
   * downloadSubtitleText 内完成）。站点有反爬策略，解析失败时静默降级为空。
   */
  private static async searchZimuku(query: string): Promise<OnlineSubtitleResult[]> {
    const results: OnlineSubtitleResult[] = [];
    const url = `https://so.zimuku.org/search?q=${encodeURIComponent(query)}`;
    const req = new rcp.Request(url, 'GET', {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'zh-CN,zh;q=0.9'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 6000, transferMs: 12000 } }
    };
    const resp = await SubtitleService.getSession().fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return results;
    }
    const html = resp.toString() || '';
    const seen = new Set<string>();
    const pattern = /href="(https?:\/\/[^"]*?\/detail\/\d+\.html|\/detail\/\d+\.html)"[^>]*?(?:title="([^"]+)")?/g;
    let m = pattern.exec(html);
    while (m && results.length < 8) {
      const href = m[1];
      const full = href.startsWith('http') ? href : `https://zimuku.org${href}`;
      const title = (m[2] || '').trim();
      if (full && !seen.has(full)) {
        seen.add(full);
        const nameForLang = title || full;
        const detected = Formatters.detectSubtitleLanguage(nameForLang, results.length);
        const lowerName = nameForLang.toLowerCase();
        results.push({
          id: `zmk_${full}`,
          title: title || `字幕库字幕 #${full.substring(full.lastIndexOf('/') + 1)}`,
          language: detected.lang,
          langLabel: detected.label,
          format: lowerName.includes('.ass') ? 'ASS' : 'SRT/ZIP',
          downloadUrl: full,
          sourceName: '字幕库'
        });
      }
      m = pattern.exec(html);
    }
    return results;
  }

  /** 季集感知评分：季集 token 命中 > 中文/双语 > ASS 特效格式 > 标题词重叠。 */
  static rankSubtitleResults(
    results: OnlineSubtitleResult[],
    videoFileName: string,
    query: string
  ): OnlineSubtitleResult[] {
    const videoLower = (videoFileName || '').toLowerCase();
    const seMatch = videoLower.match(/s\d{1,2}e\d{1,3}/);
    const seToken = seMatch ? seMatch[0] : '';
    const qTokens = query.toLowerCase().split(/[^a-z0-9\u4e00-\u9fa5]+/).filter(t => t.length > 1);

    const scored: ScoredSubtitle[] = results.map((r: OnlineSubtitleResult): ScoredSubtitle => {
      const n = r.title.toLowerCase();
      let score = 0;
      if (seToken && n.includes(seToken)) score += 4;
      if (r.language === 'zh' || r.language === 'zh-en') score += 2;
      else if (r.language === 'en') score += 1;
      if (r.format === 'ASS') score += 1;
      for (let i = 0; i < qTokens.length; i++) {
        if (n.includes(qTokens[i])) score += 0.5;
      }
      const item: ScoredSubtitle = { result: r, score };
      return item;
    });
    scored.sort((a, b) => b.score - a.score);

    const out: OnlineSubtitleResult[] = [];
    const seenKey = new Set<string>();
    for (let i = 0; i < scored.length; i++) {
      const r = scored[i].result;
      const key = `${r.title}|${r.language}`;
      if (seenKey.has(key)) continue;
      seenKey.add(key);
      out.push(r);
    }
    return out;
  }

  /**
   * 下载并返回字幕文本。字幕库来源需要两跳：先抓详情页提取压缩包直链，
   * 下载 ZIP 后解压取第一条 .srt / .ass / .ssa。cacheDir 由调用方传入。
   */
  static async downloadSubtitleText(url: string, cacheDir: string = ''): Promise<string> {
    if (url.startsWith('osdl://')) {
      const fileId = url.substring('osdl://download?file_id='.length);
      return SubtitleService.downloadOpenSubtitles(fileId, cacheDir);
    }
    if (url.includes('/detail/')) {
      return SubtitleService.downloadZimukuSubtitle(url, cacheDir);
    }
    const req = new rcp.Request(url, 'GET', {
      'User-Agent': 'PrismPlayer/1.0'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 8000, transferMs: 15000 } }
    };
    const resp = await SubtitleService.getSession().fetch(req);
    if (resp.statusCode >= 400) {
      throw new Error(`字幕下载失败 (HTTP ${resp.statusCode})`);
    }
    return resp.toString() || '';
  }

  private static async fetchBinary(url: string): Promise<ArrayBuffer> {
    const req = new rcp.Request(url, 'GET', {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      'Referer': 'https://zimuku.org/',
      'Accept': '*/*'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 8000, transferMs: 20000 } }
    };
    const resp = await SubtitleService.getSession().fetch(req);
    if (resp.statusCode >= 400) {
      throw new Error(`字幕下载失败 (HTTP ${resp.statusCode})`);
    }
    const body = resp.body;
    if (!body) {
      throw new Error('字幕下载内容为空');
    }
    return body;
  }

  private static async downloadOpenSubtitles(fileId: string, cacheDir: string): Promise<string> {
    const req = new rcp.Request(`https://api.opensubtitles.com/api/v1/download?file_id=${encodeURIComponent(fileId)}`, 'GET', {
      'Api-Key': AppConstants.OPENSUBTITLES_API_KEY,
      'Authorization': `Bearer ${AppConstants.OPENSUBTITLES_USER_TOKEN}`,
      'User-Agent': 'PrismPlayer v1.0',
      'Accept': 'application/json'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 8000, transferMs: 15000 } }
    };
    const resp = await SubtitleService.getSession().fetch(req);
    if (resp.statusCode >= 400) {
      throw new Error(`字幕下载请求失败 (HTTP ${resp.statusCode})`);
    }
    const parsed = JSON.parse(resp.toString() || '{}') as OpenSubtitlesDownloadResp;
    if (!parsed.link) {
      throw new Error('未获取到字幕下载地址，请稍后重试');
    }
    const bin = await SubtitleService.fetchBinary(parsed.link);
    const bytes = new Uint8Array(bin);
    if (bytes.length > 2 && bytes[0] === 0x50 && bytes[1] === 0x4B) {
      return SubtitleService.extractSubtitleFromZip(bin, cacheDir);
    }
    return SubtitleService.binToText(bin);
  }

  private static async downloadZimukuSubtitle(detailUrl: string, cacheDir: string): Promise<string> {
    const pageReq = new rcp.Request(detailUrl, 'GET', {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      'Referer': 'https://zimuku.org/',
      'Accept': 'text/html'
    });
    pageReq.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 6000, transferMs: 12000 } }
    };
    const pageResp = await SubtitleService.getSession().fetch(pageReq);
    if (pageResp.statusCode < 200 || pageResp.statusCode >= 300) {
      throw new Error(`字幕详情页获取失败 (HTTP ${pageResp.statusCode})`);
    }
    const html = pageResp.toString() || '';

    // 优先寻找压缩包直链，其次直接的字幕文本链接
    let direct = '';
    const zipMatch = html.match(/href="(https?:\/\/[^"]+?\.(?:zip|rar))"/i);
    if (zipMatch) direct = zipMatch[1];
    if (!direct) {
      const subMatch = html.match(/href="(https?:\/\/[^"]+?\.(?:srt|ass|ssa))"/i);
      if (subMatch) direct = subMatch[1];
    }
    if (!direct) {
      const relMatch = html.match(/href="((?:\/|https?:\/\/)[^"]*?(?:download|dld|\/d\/)[^"]*)"/i);
      if (relMatch) direct = relMatch[1].startsWith('http') ? relMatch[1] : `https://zimuku.org${relMatch[1]}`;
    }
    if (!direct) {
      throw new Error('未在该字幕详情页找到下载直链，可尝试其他字幕');
    }

    const lower = direct.toLowerCase();
    if (lower.endsWith('.rar')) {
      throw new Error('该字幕为 RAR 压缩包暂不支持，请换一条结果');
    }

    if (lower.endsWith('.srt') || lower.endsWith('.ass') || lower.endsWith('.ssa')) {
      const bin = await SubtitleService.fetchBinary(direct);
      return SubtitleService.binToText(bin);
    }

    // ZIP 压缩包：落盘 → 解压 → 取第一条字幕文件
    if (!cacheDir) {
      throw new Error('内部缓存目录不可用，无法解压字幕压缩包');
    }
    const bin = await SubtitleService.fetchBinary(direct);
    return SubtitleService.extractSubtitleFromZip(bin, cacheDir);
  }

  /** ZIP 压缩包落盘解压，取第一条字幕文件文本（优先 ASS 特效字幕）。 */
  private static async extractSubtitleFromZip(bin: ArrayBuffer, cacheDir: string): Promise<string> {
    if (!cacheDir) {
      throw new Error('内部缓存目录不可用，无法解压字幕压缩包');
    }
    const stamp = Date.now();
    const zipPath = `${cacheDir}/sub_${stamp}.zip`;
    const destDir = `${cacheDir}/sub_${stamp}_ext`;
    const zipFile = fs.openSync(zipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(zipFile.fd, bin);
    fs.closeSync(zipFile.fd);
    try {
      await zlib.decompressFile(zipPath, destDir);
      const names = await fs.listFile(destDir);
      let picked = '';
      for (let i = 0; i < names.length; i++) {
        const n = names[i].toLowerCase();
        if (n.endsWith('.srt') || n.endsWith('.ass') || n.endsWith('.ssa')) {
          picked = names[i];
          if (n.endsWith('.ass')) break; // 优先特效字幕
        }
      }
      if (!picked) {
        throw new Error('压缩包内没有可用的字幕文件');
      }
      const subFile = fs.openSync(`${destDir}/${picked}`, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(subFile.fd);
      const buf = new ArrayBuffer(Math.min(stat.size, 8 * 1024 * 1024));
      fs.readSync(subFile.fd, buf);
      fs.closeSync(subFile.fd);
      return SubtitleService.binToText(buf);
    } finally {
      try { fs.unlinkSync(zipPath); } catch (_e) { /* best effort cleanup */ }
      try { fs.rmdirSync(destDir); } catch (_e) { /* best effort cleanup */ }
    }
  }

  /** 压缩包内常见 GBK/BOM 处理：优先 UTF-8 解码，失败回退尝试 UTF-16LE，仍失败返回替换字符版本。 */
  private static binToText(bin: ArrayBuffer): string {
    const bytes = new Uint8Array(bin);
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return util.TextDecoder.create('utf-16le').decodeToString(bytes.subarray(2));
    }
    try {
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (_e) {
      return util.TextDecoder.create('gb18030').decodeToString(bytes);
    }
  }

  /**
   * Translates a foreign subtitle cue to Simplified Chinese with in-memory caching.
   * Skips text that already contains Chinese characters.
   */
  static async translateToChinese(text: string): Promise<string> {
    const clean = (text || '').trim();
    if (!clean) return '';
    if (/[\u4e00-\u9fff]/.test(clean)) {
      return clean;
    }
    const cached = SubtitleService.translationCache.get(clean);
    if (cached !== undefined) {
      return cached;
    }

    try {
      const apiUrl = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=${encodeURIComponent(clean)}`;
      const req = new rcp.Request(apiUrl, 'GET', {
        'User-Agent': 'Mozilla/5.0'
      });
      req.configuration = {
        security: { remoteValidation: 'skip' },
        transfer: { timeout: { connectMs: 4000, transferMs: 6000 } }
      };
      const resp = await SubtitleService.getSession().fetch(req);
      if (resp.statusCode === 200) {
        const body = resp.toString() || '';
        const arr = JSON.parse(body) as Object[];
        if (Array.isArray(arr) && Array.isArray(arr[0])) {
          const segs = arr[0] as Object[];
          let out = '';
          for (let i = 0; i < segs.length; i++) {
            const seg = segs[i] as string[];
            if (Array.isArray(seg) && typeof seg[0] === 'string') {
              out += seg[0];
            }
          }
          if (out) {
            SubtitleService.translationCache.set(clean, out);
            return out;
          }
        }
      }
    } catch (_e) {
      // Fallback gracefully to original text
    }
    return clean;
  }

  static getCachedTranslation(text: string): string {
    return SubtitleService.translationCache.get((text || '').trim()) || '';
  }

  /** Uses HarmonyOS @kit.CoreSpeechKit native TTS engine to read translated subtitles aloud. */
  static async speakSubtitle(text: string): Promise<void> {
    const clean = (text || '').trim();
    if (!clean || clean === SubtitleService.lastSpokenText) return;
    SubtitleService.lastSpokenText = clean;

    try {
      if (!SubtitleService.ttsEngine && !SubtitleService.ttsCreating) {
        SubtitleService.ttsCreating = true;
        const initParams: textToSpeech.CreateEngineParams = {
          language: 'zh-CN',
          person: 0,
          online: 1,
          extraParams: { 'style': 'interaction-broadcast', 'locate': 'CN', 'name': 'PrismTTS' }
        };
        SubtitleService.ttsEngine = await textToSpeech.createEngine(initParams);
        SubtitleService.ttsCreating = false;
      }
      if (SubtitleService.ttsEngine) {
        const speakParams: textToSpeech.SpeakParams = {
          requestId: `tts_${Date.now()}`,
          extraParams: {
            'speed': 1.15,
            'volume': 1.0,
            'pitch': 1.0,
            'languageContext': 'zh-CN',
            'audioType': 'pcm'
          }
        };
        SubtitleService.ttsEngine.speak(clean, speakParams);
      }
    } catch (_e) {
      SubtitleService.ttsCreating = false;
    }
  }

  static stopSpeaking(): void {
    SubtitleService.lastSpokenText = '';
    try {
      if (SubtitleService.ttsEngine) {
        SubtitleService.ttsEngine.stop();
      }
    } catch (_e) {
      // Ignore
    }
  }
}

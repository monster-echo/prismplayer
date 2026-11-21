import { textToSpeech } from '@kit.CoreSpeechKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/Constants';
import { Formatters } from '../common/Formatters';
import prismNative from 'libprismplayer.so';

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

interface EpisodeMeta {
  season: number;
  episode: number;
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
  private static translationPending: Set<string> = new Set<string>();
  private static translationFailed: Set<string> = new Set<string>();

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
    subdlApiKey: string = '',
    seasonNo: number = 0,
    episodeNo: number = 0
  ): Promise<OnlineSubtitleResult[]> {
    const cleanQ = (query || '').trim();
    if (!cleanQ) return [];
    const merged: OnlineSubtitleResult[] = [];
    const subdl = await SubtitleService.searchSubdl(cleanQ, langFilter, subdlApiKey, seasonNo, episodeNo).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'subdl error %{public}s', e.message);
      return [] as OnlineSubtitleResult[];
    });
    for (let i = 0; i < subdl.length; i++) merged.push(subdl[i]);
    const osResults = await SubtitleService.searchOpenSubtitlesProvider(cleanQ, langFilter, seasonNo, episodeNo).catch(() => [] as OnlineSubtitleResult[]);
    for (let i = 0; i < osResults.length; i++) merged.push(osResults[i]);
    const assrt = await SubtitleService.searchAssrt(cleanQ, langFilter, seasonNo, episodeNo).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'assrt error %{public}s', e.message);
      return [] as OnlineSubtitleResult[];
    });
    for (let i = 0; i < assrt.length; i++) merged.push(assrt[i]);
    const zimuku = await SubtitleService.searchZimuku(cleanQ).catch((e: Error) => {
      hilog.error(0x0001, 'PrismSub', 'zimuku error %{public}s', e.message);
      return [] as OnlineSubtitleResult[];
    });
    for (let i = 0; i < zimuku.length; i++) merged.push(zimuku[i]);
    hilog.info(0x0001, 'PrismSub', 'searchAll q=%{public}s se=%{public}d-%{public}d subdl=%{public}d os=%{public}d assrt=%{public}d zimuku=%{public}d', cleanQ, seasonNo, episodeNo, subdl.length, osResults.length, assrt.length, zimuku.length);
    return SubtitleService.rankSubtitleResults(merged, videoFileName, cleanQ, langFilter);
  }

  /** 兼容旧调用方：等价于 searchAllSubtitles。 */
  static async searchOnlineSubtitles(query: string, langFilter: string = 'all'): Promise<OnlineSubtitleResult[]> {
    return SubtitleService.searchAllSubtitles(query, '', langFilter);
  }

  private static async searchSubdl(
    query: string,
    langFilter: string,
    apiKey: string = '',
    seasonNo: number = 0,
    episodeNo: number = 0
  ): Promise<OnlineSubtitleResult[]> {
    const results: OnlineSubtitleResult[] = [];
    const langParam = langFilter !== 'all' ? `&languages=${encodeURIComponent(langFilter.toUpperCase())}` : '';
    const seParam = seasonNo > 0 && episodeNo > 0 ? `&season_number=${seasonNo}&episode_number=${episodeNo}` : '';
    // 用户在设置中自定义的 Key 优先；未配置时使用内置凭据（应用内不展示）
    const effectiveKey = apiKey.trim() || AppConstants.SUBDL_API_KEY;
    const keyParam = `&api_key=${encodeURIComponent(effectiveKey)}`;
    const subdlUrl = `https://api.subdl.com/api/v1/subtitles?film_name=${encodeURIComponent(query)}${seParam}${langParam}${keyParam}&subs_per_page=20`;
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
  private static async searchOpenSubtitlesProvider(
    query: string,
    langFilter: string,
    seasonNo: number = 0,
    episodeNo: number = 0
  ): Promise<OnlineSubtitleResult[]> {
    const results: OnlineSubtitleResult[] = [];
    const langParam = langFilter !== 'all' ? `&languages=${encodeURIComponent(langFilter)}` : '';
    const seParam = seasonNo > 0 && episodeNo > 0 ? `&season_number=${seasonNo}&episode_number=${episodeNo}` : '';
    const url = `https://api.opensubtitles.com/api/v1/subtitles?query=${encodeURIComponent(query)}${seParam}${langParam}&page_size=20`;
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
   * Assrt（射手网伪）中文源：搜索页直接给出 /download/{id}/{name}.zip 直链，
   * 支持中文/双语 ASS/SRT，不需要登录或人机验证。
   */
  private static async searchAssrt(
    query: string,
    langFilter: string,
    seasonNo: number = 0,
    episodeNo: number = 0
  ): Promise<OnlineSubtitleResult[]> {
    const results: OnlineSubtitleResult[] = [];
    const seToken = seasonNo > 0 && episodeNo > 0
      ? ` S${('0' + seasonNo).slice(-2)}E${('0' + episodeNo).slice(-2)}`
      : '';
    const url = `https://assrt.net/sub/?searchword=${encodeURIComponent(query + seToken)}`;
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
    if (resp.statusCode < 200 || resp.statusCode >= 300) return results;
    const html = resp.toString() || '';
    const blocks = html.split('class="subitem"');
    for (let i = 1; i < blocks.length && results.length < 12; i++) {
      const block = blocks[i];
      const titleMatch = block.match(/class="introtitle"[^>]*>([\s\S]*?)<\/a>/);
      const dlMatch = block.match(/\/download\/\d+\/[^'"]+/);
      if (!titleMatch || !dlMatch) continue;
      const rawTitle = titleMatch[1].replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').trim();
      if (!rawTitle) continue;
      const hasZh = /sublangchs|sublangcht/.test(block);
      const hasEn = /sublangeng/.test(block);
      if (langFilter === 'zh' && !hasZh) continue;
      if (langFilter === 'en' && !hasEn) continue;
      const formatMatch = block.match(/格式：\s*([^<]+)/);
      const formatText = formatMatch ? formatMatch[1].trim().toUpperCase() : rawTitle.toUpperCase();
      const downloadPath = dlMatch[0];
      const idMatch = downloadPath.match(/\/download\/(\d+)\//);
      const lang = hasZh && hasEn ? 'zh-en' : (hasZh ? 'zh' : 'en');
      results.push({
        id: `assrt_${idMatch ? idMatch[1] : results.length}`,
        title: rawTitle,
        language: lang,
        langLabel: lang === 'zh-en' ? '中英双语' : (lang === 'zh' ? '中文' : '英文'),
        format: formatText.includes('ASS') || formatText.includes('SSA') ? 'ASS' : 'SRT',
        downloadUrl: `https://assrt.net${downloadPath}`,
        sourceName: '射手网'
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

  /** 语言筛选：只过滤已知语言；未知语言保留，避免误删。 */
  private static matchesLanguageFilter(language: string, langFilter: string): boolean {
    if (langFilter === 'all') return true;
    const lang = (language || '').toLowerCase();
    if (!lang || lang === 'und' || lang.startsWith('track_')) return true;
    if (lang === langFilter) return true;
    // 双语字幕同时满足中文 / 英文筛选
    if (lang === 'zh-en' && (langFilter === 'zh' || langFilter === 'en')) return true;
    return false;
  }

  /** Parses SxxExx / Sxx.xx / 1x02 / EP02 / 第2集 / 01002 / Season 1 from a result title. */
  private static extractEpisodeMeta(title: string): EpisodeMeta {
    const lower = (title || '').toLowerCase();
    let m = lower.match(/s(\d{1,2})[ ._-]?e(\d{1,3})/);
    if (m) return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
    m = lower.match(/(\d{1,2})x(\d{1,3})/);
    if (m) return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
    m = lower.match(/s(\d{1,2})[ .](\d{1,3})/);
    if (m) return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
    m = lower.match(/第\s*(\d{1,3})\s*[集话]/);
    if (m) return { season: 0, episode: parseInt(m[1], 10) };
    m = lower.match(/[._\s-]e(?:p)?(\d{1,3})(?:[._\s-]|$)/);
    if (m) return { season: 0, episode: parseInt(m[1], 10) };
    m = lower.match(/\b0(\d{1,2})(\d{3})\b/);
    if (m) return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
    m = lower.match(/season[ ._-]?(\d{1,2})/);
    if (m) return { season: parseInt(m[1], 10), episode: 0 };
    m = lower.match(/(?:^|[ ._-])s(\d{1,2})(?:[ ._-]|$)/);
    if (m) return { season: parseInt(m[1], 10), episode: 0 };
    return { season: 0, episode: 0 };
  }

  static isExactEpisodeResult(title: string, seasonNo: number, episodeNo: number): boolean {
    if (seasonNo <= 0 || episodeNo <= 0) return false;
    const meta = SubtitleService.extractEpisodeMeta(title);
    return meta.season === seasonNo && meta.episode === episodeNo;
  }

  /** 季集感知评分：季集 token 命中 > 中文/双语 > ASS 特效格式 > 标题词重叠。 */
  static rankSubtitleResults(
    results: OnlineSubtitleResult[],
    videoFileName: string,
    query: string,
    langFilter: string = 'all'
  ): OnlineSubtitleResult[] {
    const videoLower = (videoFileName || '').toLowerCase();
    const seMatch = videoLower.match(/s(\d{1,2})[ ._-]?e(\d{1,3})/);
    const targetSeason = seMatch ? parseInt(seMatch[1], 10) : 0;
    const targetEpisode = seMatch ? parseInt(seMatch[2], 10) : 0;
    const qTokens = query.toLowerCase().split(/[^a-z0-9\u4e00-\u9fa5]+/).filter(t => t.length > 1);

    const candidates = results.filter((r: OnlineSubtitleResult) => {
      if (langFilter !== 'all' && !SubtitleService.matchesLanguageFilter(r.language, langFilter)) return false;
      if (targetSeason > 0) {
        const meta = SubtitleService.extractEpisodeMeta(r.title);
        // Never show an explicitly different season; same-season packs remain as fallback.
        if (meta.season > 0 && meta.season !== targetSeason) return false;
      }
      return true;
    });
    const scored: ScoredSubtitle[] = candidates.map((r: OnlineSubtitleResult): ScoredSubtitle => {
      const n = r.title.toLowerCase();
      let score = 0;
      const meta = SubtitleService.extractEpisodeMeta(n);
      if (targetSeason > 0 && targetEpisode > 0) {
        if (meta.season === targetSeason && meta.episode === targetEpisode) score += 14;
        else if (meta.season === targetSeason && meta.episode === 0) score += 3;
        else if (meta.season === targetSeason) score += 1;
      }
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

    // Prefer exact episode results when they exist; season packs are only a fallback.
    let exact: ScoredSubtitle[] = [];
    if (targetSeason > 0 && targetEpisode > 0) {
      exact = scored.filter((s: ScoredSubtitle) => SubtitleService.isExactEpisodeResult(s.result.title, targetSeason, targetEpisode));
    }
    const finalScored = exact.length > 0 ? exact : scored;

    const out: OnlineSubtitleResult[] = [];
    const seenKey = new Set<string>();
    for (let i = 0; i < finalScored.length; i++) {
      const r = finalScored[i].result;
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
  static async downloadSubtitleText(url: string, cacheDir: string = '', preferred: string = ''): Promise<string> {
    const path = (url || '').toLowerCase().split('?')[0];
    if (path.endsWith('.rar')) {
      const bin = await SubtitleService.fetchBinary(url);
      return SubtitleService.extractSubtitleFromArchive(bin, cacheDir, preferred);
    }
    if (path.endsWith('.zip')) {
      hilog.info(0x0001, 'PrismSub', 'download zip %{public}s cache=%{public}s', path, cacheDir ? 'yes' : 'no');
      const bin = await SubtitleService.fetchBinary(url);
      // 扩展名不可信：按文件头判定是 ZIP 还是 RAR
      return SubtitleService.extractSubtitleFromArchive(bin, cacheDir, preferred);
    }
    if (url.startsWith('osdl://')) {
      const fileId = url.substring('osdl://download?file_id='.length);
      return SubtitleService.downloadOpenSubtitles(fileId, cacheDir, preferred);
    }
    if (url.includes('/detail/')) {
      return SubtitleService.downloadZimukuSubtitle(url, cacheDir, preferred);
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
    const referer = url.indexOf('assrt.net') >= 0 ? 'https://assrt.net/' : 'https://zimuku.org/';
    const req = new rcp.Request(url, 'GET', {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      'Referer': referer,
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

  private static async downloadOpenSubtitles(fileId: string, cacheDir: string, preferred: string = ''): Promise<string> {
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
      return SubtitleService.extractSubtitleFromZip(bin, cacheDir, preferred);
    }
    return SubtitleService.decodeSubtitleBytes(bin, preferred);
  }

  private static async downloadZimukuSubtitle(detailUrl: string, cacheDir: string, preferred: string = ''): Promise<string> {
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
    if (lower.endsWith('.srt') || lower.endsWith('.ass') || lower.endsWith('.ssa')) {
      const bin = await SubtitleService.fetchBinary(direct);
      return SubtitleService.decodeSubtitleBytes(bin, preferred);
    }

    // 压缩包：落盘 → 解包（ZIP/RAR 由文件头判定）→ 取第一条字幕文件
    if (!cacheDir) {
      throw new Error('内部缓存目录不可用，无法解压字幕压缩包');
    }
    const bin = await SubtitleService.fetchBinary(direct);
    return SubtitleService.extractSubtitleFromArchive(bin, cacheDir, preferred);
  }

  /**
   * 压缩包落盘解包，取第一条字幕文件文本（优先 ASS 特效字幕）。
   *
   * 按**文件头**判断格式而非扩展名：字幕站常把 RAR 挂成 .zip，反之亦然。
   * RAR 走 vendored UnRAR，ZIP 走系统 zlib。
   */
  private static extractSubtitleFromArchive(bin: ArrayBuffer, cacheDir: string, preferred: string = ''): Promise<string> {
    const isRar = SubtitleService.looksLikeRar(bin);
    const stamp = Date.now();
    if (!cacheDir) {
      return Promise.reject(new Error('内部缓存目录不可用，无法解压字幕压缩包'));
    }
    if (isRar) {
      return SubtitleService.extractSubtitleFromRar(bin, cacheDir, preferred, stamp);
    }
    return SubtitleService.extractSubtitleFromZip(bin, cacheDir, preferred);
  }

  /** RAR 魔数：RAR4 "Rar!\x1a\x07\x00" / RAR5 "Rar!\x1a\x07\x01\x00" */
  private static looksLikeRar(bin: ArrayBuffer): boolean {
    if (!bin || bin.byteLength < 7) return false;
    const b = new Uint8Array(bin, 0, 7);
    return b[0] === 0x52 && b[1] === 0x61 && b[2] === 0x72 && b[3] === 0x21
      && b[4] === 0x1A && b[5] === 0x07;
  }

  private static async extractSubtitleFromRar(bin: ArrayBuffer, cacheDir: string, preferred: string, stamp: number): Promise<string> {
    const rarPath = `${cacheDir}/sub_${stamp}.rar`;
    const destDir = `${cacheDir}/sub_${stamp}_rar`;
    const fh = fs.openSync(rarPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(fh.fd, bin);
    fs.closeSync(fh.fd);
    try {
      fs.mkdirSync(destDir, true);
      const res = await prismNative.rarExtractTo(rarPath, destDir);
      if (!res.ok) {
        hilog.error(0x0001, 'PrismSub', 'unrar failed: %{public}s', res.error);
        throw new Error(`RAR 解压失败：${res.error || '未知原因'}`);
      }
      hilog.info(0x0001, 'PrismSub', 'unrar entries=%{public}d', res.names.length);
      let picked = '';
      for (const name of res.names) {
        const n = name.toLowerCase();
        if (n.endsWith('.srt') || n.endsWith('.ass') || n.endsWith('.ssa')) {
          picked = name;
          if (n.endsWith('.ass')) break;
        }
      }
      if (!picked) {
        throw new Error('压缩包内没有可用的字幕文件');
      }
      const rel = picked.replace(/\\/g, '/').replace(/^\/+/, '');
      const subFile = fs.openSync(`${destDir}/${rel}`, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(subFile.fd);
      const buf = new ArrayBuffer(Math.min(stat.size, 8 * 1024 * 1024));
      fs.readSync(subFile.fd, buf);
      fs.closeSync(subFile.fd);
      return SubtitleService.decodeSubtitleBytes(buf, preferred);
    } finally {
      try { fs.unlinkSync(rarPath); } catch (_e) { /* best effort */ }
      try { fs.rmdirSync(destDir); } catch (_e) { /* best effort */ }
    }
  }

  /** ZIP 压缩包落盘解压，取第一条字幕文件文本（优先 ASS 特效字幕）。 */
  private static async extractSubtitleFromZip(bin: ArrayBuffer, cacheDir: string, preferred: string = ''): Promise<string> {
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
      // zlib.decompressFile requires the destination directory to already exist.
      fs.mkdirSync(destDir, true);
      try {
        await zlib.decompressFile(zipPath, destDir);
      } catch (e) {
        hilog.error(0x0001, 'PrismSub', 'unzip failed: %{public}s', e instanceof Error ? e.message : String(e));
        throw new Error('字幕压缩包解压失败，请换一条结果');
      }
      const names = await fs.listFile(destDir, { recursion: true, listNum: 200 });
      hilog.info(0x0001, 'PrismSub', 'unzip entries=%{public}d', names.length);
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
      const subPath = picked.startsWith('/') ? picked.substring(1) : picked;
      const subFile = fs.openSync(`${destDir}/${subPath}`, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(subFile.fd);
      const buf = new ArrayBuffer(Math.min(stat.size, 8 * 1024 * 1024));
      fs.readSync(subFile.fd, buf);
      fs.closeSync(subFile.fd);
      return SubtitleService.decodeSubtitleBytes(buf, preferred);
    } finally {
      try { fs.unlinkSync(zipPath); } catch (_e) { /* best effort cleanup */ }
      try { fs.rmdirSync(destDir); } catch (_e) { /* best effort cleanup */ }
    }
  }

  /** Decodes subtitle bytes with BOM/UTF-8/GBK/Windows-1252 detection. */
  static decodeSubtitleBytes(bin: ArrayBuffer, preferred: string = ''): string {
    const bytes = new Uint8Array(bin);
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return util.TextDecoder.create('utf-16le').decodeToString(bytes.subarray(2));
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return util.TextDecoder.create('utf-16be').decodeToString(bytes.subarray(2));
    }

    const utf8 = SubtitleService.tryDecode(bytes, 'utf-8', true);
    if (utf8 !== null && utf8.indexOf('\uFFFD') < 0) {
      return utf8.replace(/^\uFEFF/, '');
    }

    const pref = (preferred || '').toLowerCase();
    if (pref === 'windows-1252' || pref === 'iso-8859-1') {
      const win = SubtitleService.decodeWindows1252(bytes);
      if (win) return win;
    }
    if (pref === 'gb18030' || pref === 'gbk') {
      const gb = SubtitleService.tryDecode(bytes, 'gb18030', true);
      if (gb !== null && SubtitleService.countCjk(gb) > 0) return gb;
    }

    const gb = SubtitleService.tryDecode(bytes, 'gb18030', true);
    const win = SubtitleService.decodeWindows1252(bytes);
    if (gb !== null) {
      const cjk = SubtitleService.countCjk(gb);
      const latinWords = SubtitleService.countLatinWords(gb);
      // Chinese subtitles are CJK-dominant; a Spanish file misread as GBK keeps many Latin words.
      if (cjk >= 20 && cjk > latinWords * 2) return gb;
    }
    if (win) return win;
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }

  private static tryDecode(bytes: Uint8Array, encoding: string, fatal: boolean): string | null {
    try {
      return util.TextDecoder.create(encoding, { fatal: fatal }).decodeToString(bytes);
    } catch (_e) {
      return null;
    }
  }

  private static decodeWindows1252(bytes: Uint8Array): string {
    const decoded = SubtitleService.tryDecode(bytes, 'windows-1252', false);
    if (decoded !== null) return decoded;
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }

  private static countCjk(text: string): number {
    const matches = text.match(/[\u4e00-\u9fff\u3400-\u4dbf]/g);
    return matches ? matches.length : 0;
  }

  private static countLatinWords(text: string): number {
    const matches = text.match(/[A-Za-z\u00C0-\u024F]{2,}/g);
    return matches ? matches.length : 0;
  }

  /**
   * Translates a foreign subtitle cue to Simplified Chinese with in-memory caching.
   * Skips text that already contains Chinese characters.
   */
  static requestTranslation(text: string): void {
    const clean = (text || '').trim();
    if (!clean || SubtitleService.translationCache.has(clean) || SubtitleService.translationPending.has(clean) || SubtitleService.translationFailed.has(clean)) return;
    SubtitleService.translationPending.add(clean);
    SubtitleService.translateToChinese(clean)
      .then((out: string) => {
        if (out === clean && !/[\u4e00-\u9fff]/.test(clean)) {
          SubtitleService.translationFailed.add(clean);
        }
      })
      .finally(() => { SubtitleService.translationPending.delete(clean); });
  }

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
      } else {
        hilog.warn(0x0001, 'PrismSub', 'translate http %{public}d', resp.statusCode);
      }
    } catch (e) {
      hilog.warn(0x0001, 'PrismSub', 'translate failed: %{public}s', e instanceof Error ? e.message : String(e));
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
        const offlineParams: textToSpeech.CreateEngineParams = {
          language: 'zh-CN',
          person: 0,
          online: 0,
          extraParams: { 'style': 'interaction-broadcast', 'locate': 'CN', 'name': 'PrismTTS' }
        };
        try {
          SubtitleService.ttsEngine = await textToSpeech.createEngine(offlineParams);
        } catch (_offlineError) {
          const onlineParams: textToSpeech.CreateEngineParams = {
            language: 'zh-CN',
            person: 0,
            online: 1,
            extraParams: { 'style': 'interaction-broadcast', 'locate': 'CN', 'name': 'PrismTTS' }
          };
          SubtitleService.ttsEngine = await textToSpeech.createEngine(onlineParams);
        }
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
    } catch (e) {
      SubtitleService.ttsCreating = false;
      hilog.warn(0x0001, 'PrismSub', 'tts failed: %{public}s', e instanceof Error ? e.message : String(e));
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

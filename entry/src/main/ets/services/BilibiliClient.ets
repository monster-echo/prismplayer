import { HttpHelper } from './HttpHelper';

export interface BilibiliVideoInfo {
  bvid: string;
  cid: number;
  title: string;
  coverUrl: string;
  playUrl: string;
  durationMs: number;
  qualityTag: string;
}

const BILI_HEADERS: Record<string, string> = {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
  'Referer': 'https://www.bilibili.com/'
};

/**
 * B 站分享链接解析（尽力而为）：view API 取元数据与 cid，
 * html5 playurl 取免登录的渐进式 MP4 直链（清晰度一般 360P/480P，
 * 会员/付费/地区限制视频会明确报错）。播放时 ijk 需带 Referer 头。
 */
export class BilibiliClient {
  static extractBvid(rawInput: string): string {
    const m = rawInput.match(/BV[0-9A-Za-z]{10}/);
    return m ? m[0] : '';
  }

  static isBilibiliShare(rawInput: string): boolean {
    return /bilibili\.com|b23\.tv/i.test(rawInput) || BilibiliClient.extractBvid(rawInput).length > 0;
  }

  static async resolveShareLink(rawInput: string): Promise<BilibiliVideoInfo> {
    const bvid = BilibiliClient.extractBvid(rawInput);
    if (!bvid) {
      throw new Error('未识别到 B 站视频 BV 号，请粘贴完整的分享链接');
    }

    const viewResp = await HttpHelper.requestText(
      `https://api.bilibili.com/x/web-interface/view?bvid=${bvid}`,
      { headers: BILI_HEADERS, timeoutMs: 10000 }
    );
    if (viewResp.statusCode !== 200) {
      throw new Error(`B 站元数据请求失败（${viewResp.statusCode}）`);
    }
    const viewData = JSON.parse(viewResp.body) as BilibiliViewResp;
    if (viewData.code !== 0 || !viewData.data) {
      throw new Error(viewData.message || 'B 站视频不存在或已下架');
    }
    const info = viewData.data;

    const playResp = await HttpHelper.requestText(
      `https://api.bilibili.com/x/player/playurl?bvid=${bvid}&cid=${info.cid}&qn=64&platform=html5&high_quality=1`,
      { headers: BILI_HEADERS, timeoutMs: 10000 }
    );
    if (playResp.statusCode !== 200) {
      throw new Error(`B 站播放地址请求失败（${playResp.statusCode}）`);
    }
    const playData = JSON.parse(playResp.body) as BilibiliPlayUrlResp;
    if (playData.code !== 0 || !playData.data) {
      throw new Error(playData.message || '该视频不支持免登录播放（可能是会员/付费内容）');
    }
    const durl = playData.data.durl && playData.data.durl.length > 0 ? playData.data.durl[0] : null;
    if (!durl || !durl.url) {
      throw new Error('B 站未返回可播放的直链，请稍后重试');
    }
    const quality = playData.data.quality || 16;
    return {
      bvid,
      cid: info.cid,
      title: info.title || bvid,
      coverUrl: info.pic || '',
      playUrl: durl.url,
      durationMs: (info.duration || 0) * 1000,
      qualityTag: quality >= 32 ? 'B站 480P' : 'B站 360P'
    };
  }
}

interface BilibiliViewData {
  bvid: string;
  cid: number;
  title: string;
  pic: string;
  duration: number;
}

interface BilibiliViewResp {
  code: number;
  message?: string;
  data?: BilibiliViewData;
}

interface BilibiliDurlItem {
  url: string;
  size: number;
}

interface BilibiliPlayUrlData {
  quality: number;
  durl?: BilibiliDurlItem[];
}

interface BilibiliPlayUrlResp {
  code: number;
  message?: string;
  data?: BilibiliPlayUrlData;
}

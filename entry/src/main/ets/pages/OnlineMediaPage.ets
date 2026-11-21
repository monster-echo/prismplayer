import { pasteboard } from '@kit.BasicServicesKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { BilibiliClient, BilibiliVideoInfo } from '../services/BilibiliClient';
import { DouyinClient } from '../services/DouyinClient';
import { YouTubeClient, ResolvedYouTubeStream } from '../services/YouTubeClient';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PageShell } from '../components/PageShell';
import { AppStore } from '../services/AppStore';
import { MediaItem, OnlineMediaParams, PlayerLaunchParams } from '../common/Types';

/** 通用视频链接解析：粘贴链接或分享文本，尝试直接播放或提取页面视频地址。 */
@Entry
@ComponentV2
struct OnlineMediaPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local inputText: string = '';
  @Local busy: boolean = false;
  @Local statusText: string = '';
  @Local statusOk: boolean = false;
  private linkSession: rcp.Session | null = null;

  private getLinkSession(): rcp.Session {
    if (!this.linkSession) this.linkSession = rcp.createSession();
    return this.linkSession;
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as OnlineMediaParams | undefined;
    if (params && params.clipboardUrl) {
      this.inputText = params.clipboardUrl;
    }
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private detectPlatform(text: string): string {
    if (/douyin\.com|v\.douyin/i.test(text)) return 'douyin';
    if (BilibiliClient.isBilibiliShare(text)) return 'bilibili';
    if (/youtube\.com|youtu\.be/i.test(text)) return 'youtube';
    return '';
  }

  private extractUrl(text: string): string {
    const m = text.match(/https?:\/\/[^\s]+/);
    if (!m) return text.trim();
    return m[0].replace(/[)\]）】,，。]+$/, '');
  }

  private isDirectMedia(url: string): boolean {
    return /\.(mp4|m3u8|webm|flv|mkv|mov|m4v|ts|mpd|avi)(\?|$)/i.test(url)
      || /(^|[?&])(m3u8|hls|format=mp4)([=&]|$)/i.test(url);
  }

  private decodeHtml(value: string): string {
    return value.replace(/&amp;/g, '&').replace(/&#x2F;/g, '/').replace(/&quot;/g, '"');
  }

  private resolveUrl(base: string, src: string): string {
    const clean = this.decodeHtml(src.trim());
    if (/^https?:\/\//i.test(clean)) return clean;
    if (clean.startsWith('//')) return `https:${clean}`;
    const origin = base.match(/^(https?:\/\/[^/]+)/);
    if (!origin) return clean;
    if (clean.startsWith('/')) return `${origin[1]}${clean}`;
    const dir = base.substring(0, base.lastIndexOf('/') + 1);
    return `${dir}${clean}`;
  }

  private async extractMediaUrl(pageUrl: string): Promise<string> {
    if (this.isDirectMedia(pageUrl)) return pageUrl;
    const req = new rcp.Request(pageUrl, 'GET', {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 12; HarmonyOS NEXT) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,*/*'
    });
    req.configuration = {
      security: { remoteValidation: 'skip' },
      transfer: { timeout: { connectMs: 6000, transferMs: 12000 } }
    };
    try {
      const resp = await this.getLinkSession().fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return pageUrl;
      const html = resp.toString() || '';
      const meta = html.match(/<meta[^>]+(?:property|name)=["'](?:og:video(?::url)?|twitter:player:stream)["'][^>]+content=["']([^"']+)["']/i)
        || html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["'](?:og:video(?::url)?|twitter:player:stream)["']/i);
      if (meta) return this.resolveUrl(pageUrl, meta[1]);
      const video = html.match(/<(?:video|source)[^>]+src=["']([^"']+)["']/i);
      if (video) return this.resolveUrl(pageUrl, video[1]);
      const direct = html.match(/https?:\\?\/\\?\/[^"'\s]+?\.(?:mp4|m3u8|webm|flv|mkv|mpd)(?:\?[^"'\s]*)?/i);
      if (direct) return direct[0].replace(/\\\//g, '/');
    } catch (_e) {
      // A page that cannot be parsed still gets one direct-play attempt.
    }
    return pageUrl;
  }

  private async buildGenericItem(url: string): Promise<MediaItem> {
    const streamUrl = await this.extractMediaUrl(url);
    const clean = streamUrl.split('?')[0];
    const slash = clean.lastIndexOf('/');
    const name = slash >= 0 ? clean.substring(slash + 1) : '';
    return {
      id: `url_web_${Date.now()}`,
      sourceId: 'url_web',
      sourceType: 'iptv',
      remotePath: `/url/${Date.now()}`,
      streamUrl,
      fileName: name || 'video',
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: `url_web_${Date.now()}`,
      seriesTitle: '视频',
      seasonNo: 1,
      episodeNo: 0,
      title: name || '视频链接',
      originalTitle: name || '视频链接',
      year: new Date().getFullYear(),
      overview: '',
      posterUrl: 'local://poster_bbb',
      backdropUrl: 'local://backdrop_bbb',
      rating: 0,
      qualityTag: '链接',
      tmdbId: 0,
      durationMs: 0,
      subtitleUrl: '',
      addedAt: Date.now()
    };
  }

  private buildBilibiliItem(info: BilibiliVideoInfo): MediaItem {
    return {
      id: `link_web_${info.bvid}`,
      sourceId: 'link_web',
      sourceType: 'bilibili',
      remotePath: `/link/${info.bvid}.mp4`,
      streamUrl: info.playUrl,
      fileName: `${info.bvid}.mp4`,
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: `link_web_${info.bvid}`,
      seriesTitle: '视频',
      seasonNo: 1,
      episodeNo: 0,
      title: info.title,
      originalTitle: info.title,
      year: new Date().getFullYear(),
      overview: '',
      posterUrl: info.coverUrl || 'local://poster_bbb',
      backdropUrl: info.coverUrl || 'local://backdrop_bbb',
      rating: 0,
      qualityTag: info.qualityTag,
      tmdbId: 0,
      durationMs: info.durationMs,
      subtitleUrl: '',
      addedAt: Date.now()
    };
  }

  private buildYouTubeItem(res: ResolvedYouTubeStream): MediaItem {
    const videoId = res.streamUrl.length.toString(36);
    return {
      id: `link_web_${Date.now()}_${videoId}`,
      sourceId: 'link_web',
      sourceType: 'youtube',
      remotePath: `/link/${Date.now()}.mp4`,
      streamUrl: res.streamUrl,
      fileName: 'video.mp4',
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: `link_web_${Date.now()}`,
      seriesTitle: '视频',
      seasonNo: 1,
      episodeNo: 0,
      title: res.title || '视频',
      originalTitle: res.title || '视频',
      year: new Date().getFullYear(),
      overview: '',
      posterUrl: 'local://poster_bbb',
      backdropUrl: 'local://backdrop_bbb',
      rating: 0,
      qualityTag: res.qualityTag || 'MP4',
      tmdbId: 0,
      durationMs: res.durationMs || 0,
      subtitleUrl: '',
      addedAt: Date.now()
    };
  }

  /**
   * 只有 PasteButton 安全控件能读剪贴板。
   * ohos.permission.READ_PASTEBOARD 是 system_basic 级受限权限，普通应用申请不到，
   * 直接调 pasteboard.getData() 会被系统拒（check permission failed）。
   */
  private async pasteFromClipboard(): Promise<void> {
    try {
      const pasteData = await pasteboard.getSystemPasteboard().getData();
      const text = pasteData.getPrimaryText();
      if (text && text.trim()) {
        this.inputText = text.trim();
        this.statusText = '';
      } else {
        this.statusOk = false;
        this.statusText = '剪贴板里没有文本内容';
      }
    } catch (_e) {
      this.statusOk = false;
      this.statusText = '请长按输入框手动粘贴';
    }
  }

  private async resolveAndPlay(): Promise<void> {
    const text = this.inputText.trim();
    if (!text) {
      this.statusOk = false;
      this.statusText = '请先粘贴链接';
      return;
    }
    this.busy = true;
    this.statusOk = true;
    this.statusText = '正在解析链接...';
    try {
      let item: MediaItem;
      const platform = this.detectPlatform(text);
      if (platform === 'bilibili') {
        item = this.buildBilibiliItem(await BilibiliClient.resolveShareLink(text));
      } else if (platform === 'douyin') {
        item = await this.store.resolveDouyinShareAndImport(text, false);
      } else if (platform === 'youtube') {
        item = this.buildYouTubeItem(await YouTubeClient.resolvePlayableStream(text));
      } else {
        item = await this.buildGenericItem(this.extractUrl(text));
      }
      this.busy = false;
      this.statusText = '✓ 已解析';
      const launch: PlayerLaunchParams = { item, startPositionMs: 0 };
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PlayerPage', params: launch });
    } catch (e) {
      this.busy = false;
      this.statusOk = false;
      this.statusText = e instanceof Error ? e.message : String(e);
    }
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '视频解析',
        subtitle: '粘贴链接 · 尝试播放',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 14 }) {
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    Text('链接')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    Blank()
                    PasteButton({
                      icon: PasteIconStyle.LINES,
                      text: PasteDescription.PASTE,
                      buttonType: ButtonType.Capsule
                    })
                    .height(30)
                    .padding({ left: 12, right: 12 })
                    .backgroundColor($r('app.color.bg_secondary'))
                    .fontColor($r('app.color.accent_blue'))
                    .iconColor($r('app.color.accent_blue'))
                    .borderRadius(8)
                    .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                      if (result === PasteButtonOnClickResult.SUCCESS) {
                        this.pasteFromClipboard();
                      } else {
                        this.statusOk = false;
                        this.statusText = '粘贴未获授权，请长按输入框手动粘贴';
                      }
                    })
                  }
                  .width('100%')

                  TextArea({
                    text: this.inputText,
                    placeholder: '粘贴视频、网页或分享链接'
                  })
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .placeholderColor($r('app.color.text_body_muted'))
                  .placeholderFont({ size: 12 })
                  .height(88)
                  .width('100%')
                  .borderRadius(10)
                  .backgroundColor($r('app.color.bg_primary'))
                  .border({ width: 0.8, color: $r('app.color.border_subtle') })
                  .onChange((v: string) => { this.inputText = v; })

                  if (this.statusText) {
                    Text(this.statusText)
                    .fontSize(12)
                    .fontColor(this.statusOk ? $r('app.color.success') : $r('app.color.warning'))
                    .width('100%')
                  }

                  Button() {
                    Row({ space: 6 }) {
                      if (this.busy) {
                        LoadingProgress().width(16).height(16).color(Color.White)
                      }
                      SymbolGlyph($r('sys.symbol.play_fill'))
                      .fontSize(15)
                      .fontColor([Color.White])
                      Text(this.busy ? '解析中...' : '播放')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                    }
                  }
                  .width('100%')
                  .height(44)
                  .backgroundColor($r('app.color.accent_blue'))
                  .borderRadius(11)
                  .enabled(!this.busy)
                  .onClick(() => this.resolveAndPlay())
                }
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 0.8, color: $r('app.color.border_subtle') })
                .alignItems(HorizontalAlign.Start)
              }
              .padding({ left: 18, right: 18, top: 14, bottom: 32 })
              .width('100%')
            }.edgeEffect(EdgeEffect.Spring)
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg_primary'))
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_primary'))
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

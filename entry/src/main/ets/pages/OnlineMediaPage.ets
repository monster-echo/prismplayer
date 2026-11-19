import { pasteboard } from '@kit.BasicServicesKit';
import { BilibiliClient, BilibiliVideoInfo } from '../services/BilibiliClient';
import { DouyinClient } from '../services/DouyinClient';
import { YouTubeClient } from '../services/YouTubeClient';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';
import { MediaItem, PlayerLaunchParams } from '../common/Types';
import { ResolvedYouTubeStream } from '../services/YouTubeClient';

/**
 * 网络媒体页：粘贴抖音 / B站 / YouTube 分享链接，提取播放内容后直接播放。
 * 抖音支持解析无水印流并离线保存至本地影库；B站走 html5 免登录直链（清晰度有限）。
 */
@Entry
@ComponentV2
struct OnlineMediaPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local inputText: string = '';
  @Local busy: boolean = false;
  @Local statusText: string = '';
  @Local statusOk: boolean = false;

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private detectPlatform(text: string): string {
    if (/douyin\.com|v\.douyin|抖音/i.test(text)) return 'douyin';
    if (BilibiliClient.isBilibiliShare(text)) return 'bilibili';
    if (/youtube\.com|youtu\.be/i.test(text)) return 'youtube';
    return '';
  }

  private platformLabel(p: string): string {
    return p === 'douyin' ? '抖音' : p === 'bilibili' ? 'B 站' : p === 'youtube' ? 'YouTube' : '';
  }

  private async pasteFromClipboard(): Promise<void> {
    try {
      const pasteData = await pasteboard.getSystemPasteboard().getData();
      const text = pasteData.getPrimaryText();
      if (text && text.trim()) {
        this.inputText = text.trim();
        const platform = this.detectPlatform(this.inputText);
        this.statusOk = true;
        this.statusText = platform ? `已识别：${this.platformLabel(platform)} 链接` : '';
      } else {
        this.statusOk = false;
        this.statusText = '剪贴板里没有文本内容';
      }
    } catch (_e) {
      this.statusOk = false;
      this.statusText = '读取剪贴板失败，请手动粘贴';
    }
  }

  private buildBilibiliItem(info: BilibiliVideoInfo): MediaItem {
    return {
      id: `bilibili_web_${info.bvid}`,
      sourceId: 'bilibili_web',
      sourceType: 'bilibili',
      remotePath: `/bilibili/${info.bvid}.mp4`,
      streamUrl: info.playUrl,
      fileName: `${info.bvid}.mp4`,
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: `bilibili_web_${info.bvid}`,
      seriesTitle: 'B 站视频',
      seasonNo: 1,
      episodeNo: 0,
      title: info.title,
      originalTitle: info.title,
      year: new Date().getFullYear(),
      overview: `B 站视频 · ${info.bvid}\n原始分享链接：https://www.bilibili.com/video/${info.bvid}`,
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
      id: `youtube_web_${Date.now()}_${videoId}`,
      sourceId: 'youtube_web',
      sourceType: 'youtube',
      remotePath: `/youtube/${Date.now()}.mp4`,
      streamUrl: res.streamUrl,
      fileName: 'youtube_stream.mp4',
      fileSize: 0,
      mediaType: 'movie',
      seriesKey: `youtube_web_${Date.now()}`,
      seriesTitle: 'YouTube 视频',
      seasonNo: 1,
      episodeNo: 0,
      title: res.title || 'YouTube 视频',
      originalTitle: res.title || 'YouTube 视频',
      year: new Date().getFullYear(),
      overview: 'YouTube 在线播放（解析结果有时效性，可能过期后需重新提取）',
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

  private async resolveAndPlay(saveOffline: boolean): Promise<void> {
    const text = this.inputText.trim();
    if (!text) {
      this.statusOk = false;
      this.statusText = '请先粘贴抖音 / B站 / YouTube 分享链接';
      return;
    }
    const platform = this.detectPlatform(text);
    if (!platform) {
      this.statusOk = false;
      this.statusText = '未识别到支持的平台链接（目前支持抖音 / B站 / YouTube）';
      return;
    }
    this.busy = true;
    this.statusOk = true;
    this.statusText = saveOffline
      ? `正在解析${this.platformLabel(platform)}无水印流并离线保存...`
      : `正在提取${this.platformLabel(platform)}播放内容...`;
    try {
      let item: MediaItem;
      if (platform === 'douyin') {
        item = await this.store.resolveDouyinShareAndImport(text, saveOffline);
      } else if (platform === 'bilibili') {
        const info = await BilibiliClient.resolveShareLink(text);
        item = this.buildBilibiliItem(info);
      } else {
        const res = await YouTubeClient.resolvePlayableStream(text);
        item = this.buildYouTubeItem(res);
      }
      this.busy = false;
      this.statusText = `✓ 解析成功《${item.title.substring(0, 18)}》`;
      const launch: PlayerLaunchParams = {
        item,
        startPositionMs: 0
      };
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PlayerPage', params: launch });
    } catch (e) {
      this.busy = false;
      this.statusOk = false;
      this.statusText = e instanceof Error ? e.message : String(e);
    }
  }


  @Builder
  platformChip(name: string, desc: string) {
    Column({ space: 3 }) {
      Text(name)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(desc)
        .fontSize(10)
        .fontColor($r('app.color.text_muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12, left: 8, right: 8 })
    .borderRadius(12)
    .backgroundColor($r('app.color.bg_elevated'))
    .border({ width: 0.8, color: $r('app.color.border_subtle') })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      NavHeaderBar({
        title: '网络媒体',
        subtitle: '粘贴分享链接 · 提取播放内容',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 16 }) {
          // 支持的平台
          Row({ space: 8 }) {
            this.platformChip('抖音', '无水印 · 可离线保存')
            this.platformChip('B 站', '免登录直链')
            this.platformChip('YouTube', '需可访问外网')
          }
          .width('100%')

          // 粘贴输入卡片
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('分享链接 / 口令')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Button() {
                Text('粘贴')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.accent_blue'))
              }
              .height(30)
              .padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.bg_secondary'))
              .borderRadius(8)
              .border({ width: 0.8, color: $r('app.color.border_subtle') })
              .onClick(() => this.pasteFromClipboard())
            }
            .width('100%')

            TextArea({
              text: this.inputText,
              placeholder: '粘贴抖音 / B站 / YouTube 复制的分享链接或口令全文'
            })
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_muted'))
              .placeholderFont({ size: 12 })
              .height(72)
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
                Text(this.busy ? '解析中...' : '提取并播放')
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
            .onClick(() => this.resolveAndPlay(false))

            if (this.detectPlatform(this.inputText) === 'douyin') {
              Button() {
                Text(this.busy ? '处理中...' : '解析并离线保存至影库')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .height(38)
              .backgroundColor($r('app.color.bg_elevated'))
              .borderRadius(10)
              .border({ width: 0.8, color: $r('app.color.border_subtle') })
              .enabled(!this.busy)
              .onClick(() => this.resolveAndPlay(true))
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)

          // 说明
          Column({ space: 6 }) {
            Text('使用说明').fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text('· 抖音：粘贴 App 内「复制链接」得到的口令全文，可提取无水印直链播放，并可离线保存至本地影库')
              .fontSize(11).lineHeight(17).fontColor($r('app.color.text_secondary'))
            Text('· B 站：粘贴含 BV 号的视频链接，走免登录直链（清晰度 360P/480P，会员内容不支持）')
              .fontSize(11).lineHeight(17).fontColor($r('app.color.text_secondary'))
            Text('· YouTube：解析结果有时效性，若播放失败请回到本页重新提取；需要设备可访问相应网络')
              .fontSize(11).lineHeight(17).fontColor($r('app.color.text_secondary'))
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
      }
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

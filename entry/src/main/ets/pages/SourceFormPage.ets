import { MediaArtwork } from '../common/MediaArtwork';
import {
  MediaSource,
  MediaSourceType,
  SourceExtraConfig,
  SourceFormParams,
  parseSourceExtra,
  serializeSourceExtra
} from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { AppStore } from '../services/AppStore';
import { DouyinClient } from '../services/DouyinClient';
import { RemoteSourceClient } from '../services/RemoteSourceClient';
import { WebDavTestResult } from '../services/WebDavClient';

interface NasDevicePreset {
  label: string;
  tag: string;
  type: MediaSourceType;
  url: string;
  rootPath: string;
  alist302: boolean;
  insecureTls: boolean;
  region?: string;
  mirrorUrl?: string;
}

const NAS_DEVICE_PRESETS: NasDevicePreset[] = [
  { label: '抖音分享视频', tag: '无水印/保存', type: 'douyin', url: DouyinClient.DEMO_SHARE_TEXT, rootPath: '/', alist302: false, insecureTls: true },
  { label: 'AWS S3 存储', tag: 'SigV4直连', type: 's3', url: 'https://s3.us-east-1.amazonaws.com/my-bucket', rootPath: '/', alist302: false, insecureTls: false, region: 'us-east-1' },
  { label: 'Cloudflare R2', tag: '零出流量', type: 's3', url: 'https://account-id.r2.cloudflarestorage.com/video', rootPath: '/', alist302: false, insecureTls: false, region: 'auto' },
  { label: 'MinIO 自建 S3', tag: '私有对象云', type: 's3', url: 'http://192.168.1.10:9000/movies', rootPath: '/', alist302: false, insecureTls: true, region: 'us-east-1' },
  { label: 'YouTube 频道', tag: '订阅/流播', type: 'youtube', url: 'https://www.youtube.com/@TED', rootPath: '/', alist302: false, insecureTls: false },
  { label: 'IPTV / M3U', tag: '直播/HTTP', type: 'iptv', url: 'https://iptv-org.github.io/iptv/countries/cn.m3u', rootPath: '/', alist302: false, insecureTls: true },
  { label: 'Emby / Jellyfin', tag: '海报/硬解', type: 'emby', url: 'http://192.168.1.10:8096', rootPath: '/', alist302: false, insecureTls: true },
  { label: 'SMB 共享', tag: 'SMB2/3', type: 'smb', url: 'smb://192.168.1.10/homes', rootPath: '/', alist302: false, insecureTls: false },
  { label: 'Plex 服务', tag: '海报/直连', type: 'plex', url: 'http://192.168.1.10:32400', rootPath: '/', alist302: false, insecureTls: true },
  { label: 'Alist / OpenList', tag: '302直链', type: 'alist', url: 'http://192.168.1.10:5244/dav', rootPath: '/', alist302: true, insecureTls: true },
  { label: '群晖 Synology', tag: 'DSM WebDAV', type: 'webdav', url: 'https://192.168.1.10:5006', rootPath: '/video', alist302: false, insecureTls: true }
];

@Entry
@ComponentV2
struct SourceFormPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local editingSource: MediaSource | null = null;
  @Local name: string = '我的云影源';
  @Local sourceType: MediaSourceType = 's3';
  @Local baseUrl: string = 'https://s3.us-east-1.amazonaws.com/my-bucket';
  @Local rootPath: string = '/';
  @Local username: string = '';
  @Local password: string = '';
  @Local allowInsecureTls: boolean = false;
  @Local cacheAlist302: boolean = false;

  // Protocol-specific extra config fields
  @Local s3Region: string = 'us-east-1';
  @Local s3UsePathStyle: boolean = true;
  @Local ytMirrorUrl: string = '';
  @Local ytQualityPref: string = '1080p';
  @Local iptvUserAgent: string = '';
  @Local iptvReferer: string = '';

  @Local testing: boolean = false;
  @Local testMessage: string = '';
  @Local testOk: boolean = false;
  @Local saving: boolean = false;
  @Local showAdvanced: boolean = false;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as SourceFormParams | undefined;
    if (params?.editingSource) {
      const src = params.editingSource;
      this.editingSource = src;
      this.name = src.name;
      this.sourceType = src.type;
      this.baseUrl = src.baseUrl;
      this.rootPath = src.rootPath || '/';
      this.username = src.username;
      this.password = src.password;
      this.allowInsecureTls = src.allowInsecureTls;
      this.cacheAlist302 = src.cacheAlist302;
      const extra = parseSourceExtra(src.extraConfig);
      this.s3Region = extra.region || 'us-east-1';
      this.s3UsePathStyle = extra.usePathStyle !== undefined ? extra.usePathStyle : true;
      this.ytMirrorUrl = extra.mirrorUrl || '';
      this.ytQualityPref = extra.qualityPref || '1080p';
      this.iptvUserAgent = extra.userAgent || '';
      this.iptvReferer = extra.referer || '';
    }
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private buildExtraConfig(): string {
    const extra: SourceExtraConfig = {};
    if (this.sourceType === 's3') {
      extra.region = this.s3Region.trim() || 'us-east-1';
      extra.usePathStyle = this.s3UsePathStyle;
    } else if (this.sourceType === 'youtube' || this.sourceType === 'douyin') {
      if (this.ytMirrorUrl.trim()) extra.mirrorUrl = this.ytMirrorUrl.trim();
      extra.qualityPref = this.ytQualityPref || '1080p';
    } else if (this.sourceType === 'iptv') {
      if (this.iptvUserAgent.trim()) extra.userAgent = this.iptvUserAgent.trim();
      if (this.iptvReferer.trim()) extra.referer = this.iptvReferer.trim();
    }
    return serializeSourceExtra(extra);
  }

  private buildDraft(): MediaSource {
    return {
      id: this.editingSource ? this.editingSource.id : `src_${Date.now()}`,
      name: this.name.trim() || '未命名媒体源',
      type: this.sourceType,
      baseUrl: this.baseUrl.trim(),
      rootPath: this.rootPath.trim() || '/',
      username: this.username.trim(),
      password: this.password,
      allowInsecureTls: this.allowInsecureTls,
      cacheAlist302: this.cacheAlist302,
      createdAt: this.editingSource ? this.editingSource.createdAt : Date.now(),
      lastScannedAt: this.editingSource ? this.editingSource.lastScannedAt : 0,
      extraConfig: this.buildExtraConfig()
    };
  }

  private urlFieldTitle(): string {
    if (this.sourceType === 'douyin') return '抖音分享链接或口令（直接粘贴抖音复制的全文）';
    if (this.sourceType === 's3') return 'S3 Endpoint 与存储桶（如 https://s3.us-east-1.amazonaws.com/bucket）';
    if (this.sourceType === 'youtube') return 'YouTube 链接（@频道 / 播放列表 / 单视频 / Piped 实例）';
    if (this.sourceType === 'iptv') return 'M3U 订阅链接 / HTTP 目录 / 视频直链 URL';
    if (this.sourceType === 'emby') return 'Emby / Jellyfin 地址（如 http://192.168.1.10:8096）';
    if (this.sourceType === 'smb') return 'SMB 服务器与共享名（smb://IP/共享名）';
    if (this.sourceType === 'plex') return 'Plex 服务地址（含 :32400 端口）';
    return 'WebDAV / Alist 地址（含端口与挂载前缀）';
  }

  private urlPlaceholder(): string {
    if (this.sourceType === 'douyin') return DouyinClient.DEMO_SHARE_TEXT;
    if (this.sourceType === 's3') return 'https://s3.us-east-1.amazonaws.com/my-bucket';
    if (this.sourceType === 'youtube') return 'https://www.youtube.com/@TED';
    if (this.sourceType === 'iptv') return 'https://example.com/channels.m3u';
    if (this.sourceType === 'emby') return 'http://192.168.1.10:8096';
    if (this.sourceType === 'smb') return 'smb://192.168.1.10/homes';
    if (this.sourceType === 'plex') return 'http://192.168.1.10:32400';
    return 'http://192.168.1.10:5244/dav';
  }

  private async runConnectionTest(): Promise<void> {
    if (!this.baseUrl.trim()) {
      this.testOk = false;
      this.testMessage = `请输入有效的 ${this.sourceType.toUpperCase()} 地址`;
      return;
    }
    this.testing = true;
    const statusMap: Record<string, string> = {
      'smb': '正在执行 SMB2 NTLMv2 握手...',
      'plex': '正在验证 Plex API 与媒体分区...',
      'emby': '正在验证 Emby / Jellyfin 会话...',
      's3': '正在生成 SigV4 签名并请求存储桶...',
      'youtube': '正在探测 YouTube 频道 / 视频列表...',
      'douyin': '正在解析抖音分享口令与无水印视频流...',
      'iptv': '正在解析 M3U / 流媒体响应...'
    };
    this.testMessage = statusMap[this.sourceType] || '正在执行 WebDAV PROPFIND 握手...';
    const res: WebDavTestResult = await RemoteSourceClient.testConnection(this.buildDraft());
    this.testing = false;
    this.testOk = res.ok;
    this.testMessage = res.ok ? `${res.message} · 延迟 ${res.latencyMs}ms` : res.message;
  }

  private async saveAndReturn(): Promise<void> {
    if (!this.baseUrl.trim()) {
      this.testOk = false;
      this.testMessage = '请填写有效的服务器或片源地址';
      return;
    }
    this.saving = true;
    await this.store.saveSource(this.buildDraft());
    this.saving = false;
    this.getUIContext().getRouter().back();
  }

  build() {
    Column() {
      NavHeaderBar({
        title: this.editingSource ? '编辑片源配置' : '连接云存储 / 在线 / NAS 片源',
        subtitle: 'S3 · YouTube · IPTV · Emby · SMB · Plex · WebDAV',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 16 }) {
          if (!this.editingSource) {
            Column({ space: 10 }) {
              Text('一键片源模板')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'))

              Scroll() {
                Row({ space: 10 }) {
                  ForEach(NAS_DEVICE_PRESETS, (preset: NasDevicePreset) => {
                    Column({ space: 6 }) {
                      Image(MediaArtwork.presetIcon(preset.label))
                        .width(28)
                        .height(28)
                      Text(preset.label)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                      Text(preset.tag)
                        .fontSize(10)
                        .fontColor($r('app.color.accent_cyan'))
                    }
                    .width(106)
                    .padding({ top: 12, bottom: 10, left: 8, right: 8 })
                    .borderRadius(12)
                    .backgroundColor($r('app.color.bg_elevated'))
                    .border({ width: 0.8, color: $r('app.color.fill_strong') })
                    .onClick(() => {
                      this.name = preset.label;
                      this.sourceType = preset.type;
                      this.baseUrl = preset.url;
                      this.rootPath = preset.rootPath;
                      this.cacheAlist302 = preset.alist302;
                      this.allowInsecureTls = preset.insecureTls;
                      if (preset.region) this.s3Region = preset.region;
                      if (preset.mirrorUrl !== undefined) this.ytMirrorUrl = preset.mirrorUrl;
                    })
                  }, (p: NasDevicePreset) => p.label)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .align(Alignment.TopStart)
              .scrollBar(BarState.Off)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }

          // Compact 2-row Protocol Selector
          Column({ space: 8 }) {
            Text('片源协议模式')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))

            Row({ space: 6 }) {
              this.protocolChip('抖音视频', 'douyin', $r('app.media.ic_protocol_douyin'))
              this.protocolChip('S3 云存储', 's3', $r('app.media.ic_protocol_s3'))
              this.protocolChip('YouTube', 'youtube', $r('app.media.ic_protocol_youtube'))
              this.protocolChip('IPTV/流', 'iptv', $r('app.media.ic_protocol_iptv'))
            }.width('100%')

            Row({ space: 6 }) {
              this.protocolChip('SMB 共享', 'smb', $r('app.media.ic_protocol_smb'))
              this.protocolChip('Plex', 'plex', $r('app.media.ic_protocol_plex'))
              this.protocolChip('Emby', 'emby', $r('app.media.ic_protocol_emby'))
              this.protocolChip('WebDAV', 'webdav', $r('app.media.ic_protocol_webdav'))
              this.protocolChip('Alist', 'alist', $r('app.media.ic_cloud_alist'))
            }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)

          // Core Connection Card
          Column({ space: 12 }) {
            Text('连接与地址')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))

            this.fieldLabel('显示名称')
            TextInput({ text: this.name, placeholder: '例如：我的 R2 片库 / YouTube 影评' })
              .height(42)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.bg_secondary'))
              .borderRadius(10)
              .onChange((v: string) => { this.name = v; })

            Text(this.urlFieldTitle())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.baseUrl, placeholder: this.urlPlaceholder() })
              .height(42)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.bg_secondary'))
              .borderRadius(10)
              .onChange((v: string) => { this.baseUrl = v; })

            if (this.sourceType === 's3') {
              Row({ space: 10 }) {
                Column({ space: 6 }) {
                  this.fieldLabel('Region 区域')
                  TextInput({ text: this.s3Region, placeholder: 'us-east-1 或 auto' })
                    .height(42)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.bg_secondary'))
                    .borderRadius(10)
                    .onChange((v: string) => { this.s3Region = v; })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                Column({ space: 6 }) {
                  this.fieldLabel('子目录 Prefix')
                  TextInput({ text: this.rootPath, placeholder: '/' })
                    .height(42)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.bg_secondary'))
                    .borderRadius(10)
                    .onChange((v: string) => { this.rootPath = v; })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%')
            } else if (this.sourceType === 'youtube' || this.sourceType === 'douyin') {
              Text(
                this.sourceType === 'douyin'
                  ? '自建抖音解析 API 地址（选填，如 Douyin_TikTok_Download_API）'
                  : 'Piped / Invidious 解析镜像（选填，用于加速或签名流直链）'
              )
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.ytMirrorUrl, placeholder: 'https://your-parser-api-host' })
                .height(42)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.bg_secondary'))
                .borderRadius(10)
                .onChange((v: string) => { this.ytMirrorUrl = v; })
            } else if (this.sourceType === 'smb' || this.sourceType === 'webdav' || this.sourceType === 'alist') {
              this.fieldLabel(this.sourceType === 'smb' ? '共享内子目录路径' : '初始根目录路径')
              TextInput({ text: this.rootPath, placeholder: this.sourceType === 'smb' ? '/rw/download/movie' : '/' })
                .height(42)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.bg_secondary'))
                .borderRadius(10)
                .onChange((v: string) => { this.rootPath = v; })
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })
          .alignItems(HorizontalAlign.Start)

          // Context-Specific Credentials (hidden for YouTube / Douyin / IPTV public feeds unless needed)
          if (this.sourceType !== 'youtube' && this.sourceType !== 'douyin' && this.sourceType !== 'iptv') {
            Column({ space: 12 }) {
              Row({ space: 8 }) {
                Image($r('app.media.ic_shield_vault')).width(18).height(18)
                Text(
                  this.sourceType === 's3'
                    ? 'S3 Access Key / Secret（HUKS 加密存储）'
                    : (this.sourceType === 'plex' ? 'Plex Token 鉴权（HUKS 加密存储）' : '账号鉴权（HUKS AES-256-GCM 硬件密钥库加密）')
                )
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))
              }.width('100%')

              Row({ space: 10 }) {
                Column({ space: 6 }) {
                  Text(
                    this.sourceType === 's3'
                      ? 'Access Key ID'
                      : (this.sourceType === 'plex' ? 'Plex 用户名（选填）' : (this.sourceType === 'emby' ? '用户名（API Key 可留空）' : '用户名'))
                  )
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  TextInput({ text: this.username, placeholder: this.sourceType === 's3' ? 'AKIA...（公开桶留空）' : 'admin' })
                    .height(42)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.bg_secondary'))
                    .borderRadius(10)
                    .onChange((v: string) => { this.username = v; })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                Column({ space: 6 }) {
                  Text(
                    this.sourceType === 's3'
                      ? 'Secret Access Key'
                      : (this.sourceType === 'plex' ? 'X-Plex-Token' : (this.sourceType === 'emby' ? '密码或 API Key' : '密码'))
                  )
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                  TextInput({ text: this.password, placeholder: '••••••' })
                    .type(InputType.Password)
                    .height(42)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.bg_secondary'))
                    .borderRadius(10)
                    .onChange((v: string) => { this.password = v; })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(14)
            .backgroundColor($r('app.color.bg_elevated'))
            .border({ width: 0.8, color: $r('app.color.border_subtle') })
            .alignItems(HorizontalAlign.Start)
          }

          // Collapsible Advanced Network & Protocol Options
          Column({ space: 12 }) {
            Row() {
              Column({ space: 2 }) {
                Text('高级协议与传输选项').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                Text(`自签名 TLS：${this.allowInsecureTls ? '信任' : '严格'}${this.sourceType === 's3' ? ` · PathStyle：${this.s3UsePathStyle ? '开启' : '关闭'}` : ''}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_muted'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)

              SymbolGlyph(this.showAdvanced ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('app.color.text_muted')])
            }
            .width('100%')
            .onClick(() => { this.showAdvanced = !this.showAdvanced; })

            if (this.showAdvanced) {
              Divider().color($r('app.color.divider'))

              Row() {
                Column({ space: 2 }) {
                  Text('信任局域网自签名 HTTPS 证书').fontSize(14).fontColor($r('app.color.text_primary'))
                  Text('MinIO / NAS / 内网反代推荐开启').fontSize(11).fontColor($r('app.color.text_muted'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.allowInsecureTls })
                  .selectedColor($r('app.color.accent_blue'))
                  .onChange((val: boolean) => { this.allowInsecureTls = val; })
              }.width('100%')

              if (this.sourceType === 's3') {
                Row() {
                  Column({ space: 2 }) {
                    Text('使用 S3 Path-Style URL 访问').fontSize(14).fontColor($r('app.color.text_primary'))
                    Text('MinIO / 地址末尾带桶名选开启；Virtual-Host 选关闭').fontSize(11).fontColor($r('app.color.text_muted'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.s3UsePathStyle })
                    .selectedColor($r('app.color.accent_blue'))
                    .onChange((val: boolean) => { this.s3UsePathStyle = val; })
                }.width('100%')
              }

              if (this.sourceType === 'alist') {
                Row() {
                  Column({ space: 2 }) {
                    Text('Alist 302 直链缓存优化').fontSize(14).fontColor($r('app.color.text_primary'))
                    Text('缓存重定向直链 10 分钟，降低拖动 Seek 触发风控').fontSize(11).fontColor($r('app.color.text_muted'))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Toggle({ type: ToggleType.Switch, isOn: this.cacheAlist302 })
                    .selectedColor($r('app.color.accent_blue'))
                    .onChange((val: boolean) => { this.cacheAlist302 = val; })
                }.width('100%')
              }

              if (this.sourceType === 'youtube') {
                this.fieldLabel('YouTube 首选最高清晰度')
                Row({ space: 8 }) {
                  ForEach(['1080p', '720p', '480p'], (q: string) => {
                    Text(q)
                      .layoutWeight(1)
                      .height(34)
                      .fontSize(12)
                      .fontColor(this.ytQualityPref === q ? Color.White : $r('app.color.text_secondary'))
                      .textAlign(TextAlign.Center)
                      .borderRadius(8)
                      .backgroundColor(this.ytQualityPref === q ? $r('app.color.accent_blue') : $r('app.color.bg_secondary'))
                      .onClick(() => { this.ytQualityPref = q; })
                  })
                }.width('100%')
              }

              if (this.sourceType === 'iptv') {
                this.fieldLabel('自定义 User-Agent（选填）')
                TextInput({ text: this.iptvUserAgent, placeholder: 'Lavf/58.76.100 或 PotPlayer' })
                  .height(40)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(8)
                  .onChange((v: string) => { this.iptvUserAgent = v; })
              }
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.border_subtle') })

          if (this.testMessage) {
            Row({ space: 8 }) {
              SymbolGlyph(this.testOk ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.exclamationmark_triangle_fill'))
                .fontSize(16)
                .fontColor([this.testOk ? $r('app.color.success') : $r('app.color.danger')])
              Text(this.testMessage)
                .fontSize(13)
                .fontColor(this.testOk ? $r('app.color.success') : $r('app.color.danger'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor($r('app.color.bg_elevated'))
            .border({ width: 0.8, color: this.testOk ? $r('app.color.success') : $r('app.color.danger') })
          }
        }
        .padding({ left: 18, right: 18, top: 14, bottom: 24 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)

      // Sticky Bottom Actions Bar
      Row({ space: 12 }) {
        Button(this.testing ? '测试中...' : '测试连接')
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.bg_elevated'))
          .borderRadius(12)
          .border({ width: 0.8, color: $r('app.color.fill_strong') })
          .enabled(!this.testing)
          .onClick(() => { this.runConnectionTest(); })

        Button(this.saving ? '保存中...' : '保存片源')
          .layoutWeight(1)
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(12)
          .enabled(!this.saving)
          .onClick(() => { this.saveAndReturn(); })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 10, bottom: 18 })
      .backgroundColor($r('app.color.bar_glass'))
      .border({ width: { top: 0.6 }, color: $r('app.color.fill_subtle') })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  @Builder
  protocolChip(label: string, mode: MediaSourceType, icon: Resource) {
    Button() {
      Column({ space: 3 }) {
        Image(icon).width(16).height(16)
        Text(label)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.sourceType === mode ? Color.White : $r('app.color.text_secondary'))
          .maxLines(1)
      }
    }
    .layoutWeight(1)
    .height(48)
    .backgroundColor(this.sourceType === mode ? $r('app.color.accent_blue') : $r('app.color.bg_elevated'))
    .borderRadius(10)
    .border({ width: 0.8, color: this.sourceType === mode ? $r('app.color.accent_blue') : $r('app.color.border_subtle') })
    .onClick(() => {
      const prevDefault = this.urlPlaceholder();
      this.sourceType = mode;
      this.cacheAlist302 = (mode === 'alist');
      this.testMessage = '';
      if (!this.editingSource && (!this.baseUrl.trim() || this.baseUrl.trim() === prevDefault)) {
        this.baseUrl = '';
      }
    })
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
  }
}

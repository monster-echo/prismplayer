import { MediaArtwork } from '../common/MediaArtwork';
import { PageShell } from '../components/PageShell';
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
import { PlexClient } from '../services/PlexClient';
import { RemoteSourceClient } from '../services/RemoteSourceClient';
import { WebDavTestResult } from '../services/WebDavClient';

interface SourcePreset {
  name: string;
  tag: string;
  type: MediaSourceType;
  hint: string;
  rootPath: string;
  alist302: boolean;
  insecureTls: boolean;
  region?: string;
}

/** 预设本身就是类型选择器：点一下填好名称、协议、根目录和地址示例，用户只补 IP 与账号。 */
const SOURCE_PRESETS: SourcePreset[] = [
  { name: '我的 NAS', tag: 'WebDAV', type: 'webdav', hint: 'http://192.168.1.10:5005', rootPath: '/', alist302: false, insecureTls: true },
  { name: '我的群晖', tag: '群晖 DSM', type: 'webdav', hint: 'https://192.168.1.10:5006', rootPath: '/video', alist302: false, insecureTls: true },
  { name: '我的飞牛', tag: '飞牛 fnOS', type: 'webdav', hint: 'http://192.168.1.10:5005', rootPath: '/', alist302: false, insecureTls: true },
  { name: '我的威联通', tag: '威联通 QNAP', type: 'webdav', hint: 'http://192.168.1.10:5005', rootPath: '/', alist302: false, insecureTls: true },
  { name: '我的 Alist', tag: '302 直链', type: 'alist', hint: 'http://192.168.1.10:5244/dav', rootPath: '/', alist302: true, insecureTls: true },
  { name: '我的 Plex', tag: 'Plex 服务', type: 'plex', hint: 'http://192.168.1.10:32400', rootPath: '/', alist302: false, insecureTls: true },
  { name: '我的 Emby', tag: 'Emby / Jellyfin', type: 'emby', hint: 'http://192.168.1.10:8096', rootPath: '/', alist302: false, insecureTls: true },
  { name: '我的 SMB 共享', tag: 'SMB2/3', type: 'smb', hint: 'smb://192.168.1.10/homes', rootPath: '/', alist302: false, insecureTls: false },
  { name: '对象存储', tag: 'S3 / MinIO / R2', type: 's3', hint: 'https://s3.us-east-1.amazonaws.com/my-bucket', rootPath: '/', alist302: false, insecureTls: false, region: 'us-east-1' },
  { name: '直播源', tag: 'IPTV / M3U', type: 'iptv', hint: 'https://example.com/channels.m3u', rootPath: '/', alist302: false, insecureTls: false }
];

@Entry
@ComponentV2
struct SourceFormPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local editingSource: MediaSource | null = null;
  @Local name: string = '我的 NAS';
  @Local activePreset: string = '我的 NAS';
  @Local sourceType: MediaSourceType = 'webdav';
  @Local baseUrl: string = '';
  @Local urlHint: string = 'http://192.168.1.10:5005';
  @Local rootPath: string = '/';
  @Local username: string = '';
  @Local password: string = '';
  @Local allowInsecureTls: boolean = true;
  @Local cacheAlist302: boolean = false;

  // Plex 只需要 Token；账号密码仅用于一次性换取 Token，不写进片源配置
  @Local plexLoginOpen: boolean = false;
  @Local plexLogin: string = '';
  @Local plexPassword: string = '';
  @Local plexTokenBusy: boolean = false;
  @Local plexTokenMessage: string = '';

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
      this.activePreset = '';
      this.urlHint = '';
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
      name: this.name.trim() || this.typeLabel(),
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

  private typeLabel(): string {
    if (this.sourceType === 'alist') return 'Alist';
    if (this.sourceType === 'smb') return 'SMB';
    if (this.sourceType === 'plex') return 'Plex';
    if (this.sourceType === 'emby') return 'Emby / Jellyfin';
    if (this.sourceType === 's3') return 'S3 对象存储';
    if (this.sourceType === 'iptv') return 'IPTV / M3U';
    if (this.sourceType === 'youtube') return 'YouTube';
    if (this.sourceType === 'douyin') return '抖音';
    return 'WebDAV';
  }

  private urlFieldTitle(): string {
    if (this.sourceType === 'smb') return '共享地址';
    if (this.sourceType === 's3') return 'Endpoint / 存储桶';
    if (this.sourceType === 'iptv') return '订阅或直链';
    if (this.sourceType === 'youtube' || this.sourceType === 'douyin') return '视频链接';
    return '服务器地址';
  }

  private urlPlaceholder(): string {
    if (this.urlHint) return this.urlHint;
    if (this.sourceType === 'emby') return 'http://192.168.1.10:8096';
    if (this.sourceType === 'plex') return 'http://192.168.1.10:32400';
    if (this.sourceType === 'smb') return 'smb://192.168.1.10/homes';
    if (this.sourceType === 's3') return 'https://s3.us-east-1.amazonaws.com/my-bucket';
    if (this.sourceType === 'iptv') return 'https://example.com/channels.m3u';
    if (this.sourceType === 'youtube' || this.sourceType === 'douyin') return 'https://...';
    return 'http://192.168.1.10:5005';
  }

  private async runConnectionTest(): Promise<void> {
    if (!this.baseUrl.trim()) {
      this.testOk = false;
      this.testMessage = `请输入有效的 ${this.typeLabel()} 地址`;
      return;
    }
    this.testing = true;
    const statusMap: Record<string, string> = {
      'smb': '正在执行 SMB2 NTLMv2 握手...',
      'plex': '正在验证 Plex API 与媒体分区...',
      'emby': '正在验证 Emby / Jellyfin 会话...',
      's3': '正在生成 SigV4 签名并请求存储桶...',
      'youtube': '正在解析视频链接...',
      'douyin': '正在解析视频链接...',
      'iptv': '正在解析 M3U / 流媒体响应...'
    };
    this.testMessage = statusMap[this.sourceType] || '正在执行 WebDAV PROPFIND 握手...';
    const res: WebDavTestResult = await RemoteSourceClient.testConnection(this.buildDraft());
    this.testing = false;
    this.testOk = res.ok;
    this.testMessage = res.ok ? `${res.message} · 延迟 ${res.latencyMs}ms` : res.message;
  }

  /** 用 Plex 账号换取 Token，成功后直接填进 Token 输入框，账号密码不保存。 */
  private async fetchPlexToken(): Promise<void> {
    if (!this.plexLogin.trim() || !this.plexPassword) {
      this.testOk = false;
      this.plexTokenMessage = '请填写 Plex 账号和密码';
      return;
    }
    this.plexTokenBusy = true;
    this.plexTokenMessage = '';
    try {
      const token: string = await PlexClient.signIn(this.plexLogin, this.plexPassword);
      this.password = token;
      this.username = '';
      this.plexPassword = '';
      this.plexLoginOpen = false;
      this.testOk = true;
      this.plexTokenMessage = '已获取 Token，可以测试连接了';
    } catch (e) {
      this.testOk = false;
      this.plexTokenMessage = e instanceof Error ? e.message : String(e);
    } finally {
      this.plexTokenBusy = false;
    }
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
        title: this.editingSource ? '编辑片源' : '添加片源',
        subtitle: this.editingSource ? this.typeLabel() : '',
        onBack: () => this.getUIContext().getRouter().back()
      })

      Stack() {
        PageShell({ maxWidth: 760 }) {
          Column() {

            Scroll() {
              Column({ space: 16 }) {
                Column({ space: 10 }) {
                  Text(this.editingSource ? `类型 · ${this.typeLabel()}` : '类型')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))

                  if (!this.editingSource) {
                    Scroll() {
                      Row({ space: 10 }) {
                        ForEach(SOURCE_PRESETS, (preset: SourcePreset) => {
                          Column({ space: 6 }) {
                            Image(MediaArtwork.presetIcon(preset.name, preset.tag))
                            .width(28)
                            .height(28)
                            Text(preset.name)
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            Text(preset.tag)
                            .fontSize(10)
                            .fontColor($r('app.color.accent_cyan'))
                            .maxLines(1)
                          }
                          .width(106)
                          .padding({ top: 12, bottom: 10, left: 8, right: 8 })
                          .borderRadius(12)
                          .backgroundColor($r('app.color.bg_elevated'))
                          .border({ width: this.activePreset === preset.name ? 1.2 : 0.8, color: this.activePreset === preset.name ? $r('app.color.accent_blue') : $r('app.color.fill_strong') })
                          .onClick(() => {
                            this.activePreset = preset.name;
                            this.name = preset.name;
                            this.sourceType = preset.type;
                            this.urlHint = preset.hint;
                            this.rootPath = preset.rootPath;
                            this.cacheAlist302 = preset.alist302;
                            this.allowInsecureTls = preset.insecureTls;
                            this.s3Region = preset.region || this.s3Region;
                            this.testMessage = '';
                            this.plexLoginOpen = false;
                            this.plexTokenMessage = '';
                          })
                        }, (p: SourcePreset) => p.name)
                      }
                    }.edgeEffect(EdgeEffect.Spring)
                    .scrollable(ScrollDirection.Horizontal)
                    .align(Alignment.TopStart)
                    .scrollBar(BarState.Off)
                  }
                }.width('100%').alignItems(HorizontalAlign.Start)

                // Core Connection Card
                Column({ space: 12 }) {
                  Text('连接与地址')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))

                  this.fieldLabel('名称')
                  TextInput({ text: this.name, placeholder: '例如：我的 NAS' })
                  .height(42)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(10)
                  .onChange((v: string) => {
                    this.name = v;
                    this.activePreset = '';
                  })

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
                    Text('解析服务地址（选填）')
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
                    this.fieldLabel('根目录')
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
                      ? 'Access Key'
                      : (this.sourceType === 'plex' ? 'Plex Token' : '账号')
                      )
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_secondary'))
                    }.width('100%')

                    if (this.sourceType === 'plex') {
                      TextInput({ text: this.password, placeholder: '粘贴 X-Plex-Token' })
                      .type(InputType.Password)
                      .showPasswordIcon(true)
                      .height(42)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .backgroundColor($r('app.color.bg_secondary'))
                      .borderRadius(10)
                      .onChange((v: string) => { this.password = v; })

                      Text('Plex Web → 影片「⋯」→ 获取信息 → 查看 XML，链接里的 X-Plex-Token')
                      .fontSize(11)
                      .fontColor($r('app.color.text_body_muted'))
                      .maxLines(2)

                      Row({ space: 6 }) {
                        Text(this.plexLoginOpen ? '收起账号登录' : '不知道 Token？用 Plex 账号换取')
                        .fontSize(12)
                        .fontColor($r('app.color.accent_blue'))
                      }
                      .width('100%')
                      .onClick(() => {
                        this.plexLoginOpen = !this.plexLoginOpen;
                        this.plexTokenMessage = '';
                      })

                      if (this.plexLoginOpen) {
                        TextInput({ text: this.plexLogin, placeholder: 'Plex 账号（邮箱）' })
                        .height(42)
                        .fontSize(14)
                        .fontColor($r('app.color.text_primary'))
                        .backgroundColor($r('app.color.bg_secondary'))
                        .borderRadius(10)
                        .onChange((v: string) => { this.plexLogin = v; })

                        TextInput({ text: this.plexPassword, placeholder: 'Plex 账号密码（不保存）' })
                        .type(InputType.Password)
                        .height(42)
                        .fontSize(14)
                        .fontColor($r('app.color.text_primary'))
                        .backgroundColor($r('app.color.bg_secondary'))
                        .borderRadius(10)
                        .onChange((v: string) => { this.plexPassword = v; })

                        Button(this.plexTokenBusy ? '正在换取...' : '换取 Token')
                        .width('100%')
                        .height(38)
                        .fontSize(13)
                        .fontColor(Color.White)
                        .backgroundColor($r('app.color.accent_blue'))
                        .borderRadius(10)
                        .enabled(!this.plexTokenBusy)
                        .onClick(() => { this.fetchPlexToken(); })
                      }

                      if (this.plexTokenMessage) {
                        Text(this.plexTokenMessage)
                        .fontSize(11)
                        .fontColor(this.testOk ? $r('app.color.success') : $r('app.color.danger'))
                        .maxLines(2)
                      }
                    } else {
                      Row({ space: 10 }) {
                        Column({ space: 6 }) {
                          Text(
                          this.sourceType === 's3'
                          ? 'Access Key ID'
                          : (this.sourceType === 'emby' ? '用户名（API Key 可留空）' : '用户名')
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
                          : (this.sourceType === 'emby' ? '密码或 API Key' : '密码')
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
                      Text('高级选项').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                      Text(`自签名证书：${this.allowInsecureTls ? '信任' : '严格'}${this.sourceType === 's3' ? ` · PathStyle ${this.s3UsePathStyle ? '开' : '关'}` : ''}`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_body_muted'))
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
                        Text('MinIO / NAS / 内网反代推荐开启').fontSize(11).fontColor($r('app.color.text_body_muted'))
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Toggle({ type: ToggleType.Switch, isOn: this.allowInsecureTls })
                      .selectedColor($r('app.color.accent_blue'))
                      .onChange((val: boolean) => { this.allowInsecureTls = val; })
                    }.width('100%')

                    if (this.sourceType === 's3') {
                      Row() {
                        Column({ space: 2 }) {
                          Text('使用 S3 Path-Style URL 访问').fontSize(14).fontColor($r('app.color.text_primary'))
                          Text('MinIO / 地址末尾带桶名选开启；Virtual-Host 选关闭').fontSize(11).fontColor($r('app.color.text_body_muted'))
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
                          Text('缓存重定向直链 10 分钟，降低拖动 Seek 触发风控').fontSize(11).fontColor($r('app.color.text_body_muted'))
                        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                        Toggle({ type: ToggleType.Switch, isOn: this.cacheAlist302 })
                        .selectedColor($r('app.color.accent_blue'))
                        .onChange((val: boolean) => { this.cacheAlist302 = val; })
                      }.width('100%')
                    }

                    if (this.sourceType === 'youtube') {
                      this.fieldLabel('首选清晰度')
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
            }.edgeEffect(EdgeEffect.Spring)
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
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
  }
}
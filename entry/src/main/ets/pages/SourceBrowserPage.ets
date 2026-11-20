import { Formatters } from '../common/Formatters';
import { PageShell } from '../components/PageShell';
import { MediaArtwork } from '../common/MediaArtwork';
import {
  MediaDetailParams,
  MediaItem,
  MediaSource,
  PlayerLaunchParams,
  RemoteFileEntry,
  SourceBrowserParams
} from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';
import { PatternPad } from '../components/PatternPad';
import { AppStore } from '../services/AppStore';
import { RemoteSourceClient } from '../services/RemoteSourceClient';

type BrowserFilter = 'all' | 'video' | 'subtitle';

interface BreadcrumbSegment {
  label: string;
  path: string;
}

@Entry
@ComponentV2
struct SourceBrowserPage {
  @Local store: AppStore = AppStore.getInstance();
  @Local source: MediaSource | null = null;
  @Local currentDirPath: string = '/';
  @Local pathHistory: string[] = [];
  @Local entries: RemoteFileEntry[] = [];
  @Local loading: boolean = false;
  @Local errorText: string = '';
  @Local filterMode: BrowserFilter = 'all';
  @Local pendingHideEntry: RemoteFileEntry | null = null;
  @Local pendingPattern: string = '';
  @Local pinError: string = '';
  @Local ytSearchQuery: string = '';
  @Local savingEntryPath: string = '';
  @Local saveFeedbackText: string = '';
  @Local refreshing: boolean = false;

  private async saveEntryVideoOffline(entry: RemoteFileEntry): Promise<void> {
    if (!this.source || this.savingEntryPath) return;
    this.savingEntryPath = entry.path;
    this.saveFeedbackText = `正在下载保存《${entry.name.substring(0, 16)}》...`;
    const subUrl = this.findSiblingSubtitleUrl(entry);
    const item = await this.store.addRemoteFileToLibrary(this.source, entry, subUrl);
    const res = await this.store.saveMediaItemOffline(item, this.source, false);
    this.savingEntryPath = '';
    this.saveFeedbackText = res.ok ? `✓ ${res.message}` : res.message;
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as SourceBrowserParams | undefined;
    if (params?.source) {
      this.source = params.source;
      const startPath = params.initialPath || params.source.rootPath || '/';
      this.loadDirectory(startPath, false);
    }
  }

  onBackPress(): boolean {
    this.navigateBackOneLevel();
    return true;
  }

  private navigateBackOneLevel(): void {
    if (this.pathHistory.length > 0 && this.source) {
      const prev = this.pathHistory.pop()!;
      this.loadDirectory(prev, false);
    } else {
      this.getUIContext().getRouter().back();
    }
  }

  private async loadDirectory(dirPath: string, pushCurrent: boolean): Promise<void> {
    if (!this.source) return;
    if (pushCurrent) {
      this.pathHistory.push(this.currentDirPath);
    }
    this.currentDirPath = dirPath;
    this.loading = true;
    this.errorText = '';
    try {
      this.entries = await RemoteSourceClient.listDirectory(this.source, dirPath);
    } catch (e) {
      this.entries = [];
      this.errorText = e instanceof Error ? e.message : String(e);
    } finally {
      this.loading = false;
    }
  }

  private getBreadcrumbs(): BreadcrumbSegment[] {
    if (!this.source) return [];
    const root = (this.source.rootPath || '/').replace(/\/+$/, '') || '/';
    const crumbs: BreadcrumbSegment[] = [{ label: this.source.name, path: root }];
    const cleanCur = this.currentDirPath.replace(/\/+$/, '') || '/';
    if (cleanCur === root) return crumbs;
    let rel = cleanCur;
    if (root !== '/' && cleanCur.startsWith(root)) {
      rel = cleanCur.substring(root.length);
    }
    const parts = rel.split('/').filter(p => p.length > 0);
    let acc = root === '/' ? '' : root;
    for (let i = 0; i < parts.length; i++) {
      acc = `${acc}/${parts[i]}`;
      crumbs.push({ label: parts[i], path: acc });
    }
    return crumbs;
  }

  private getFilteredEntries(): RemoteFileEntry[] {
    const srcId = this.source ? this.source.id : '';
    const visible = srcId
      ? this.entries.filter(e => !this.store.shouldConcealPath(srcId, e.path))
      : this.entries;
    if (this.filterMode === 'video') {
      return visible.filter(e => e.isDirectory || e.isVideo);
    }
    if (this.filterMode === 'subtitle') {
      return visible.filter(e => e.isDirectory || e.isSubtitle);
    }
    return visible;
  }

  private requestHideFolder(entry: RemoteFileEntry): void {
    if (!this.source) return;
    const isAlready = this.store.isPathRuleHidden(this.source.id, entry.path);
    if (isAlready) {
      const norm = (entry.path || '/').replace(/\\/g, '/').replace(/\/+$/, '') || '/';
      const ruleId = `${this.source.id}::${norm.startsWith('/') ? norm : '/' + norm}`;
      this.store.unhideFolder(ruleId);
      return;
    }
    if (!this.store.hasVaultPattern()) {
      this.pendingHideEntry = entry;
      this.pendingPattern = '';
      this.pinError = '';
      return;
    }
    this.store.hideFolderToVault(this.source.id, entry.path, entry.name);
  }

  private async onPattern(pattern: string): Promise<void> {
    if (!this.pendingHideEntry || !this.source) return;
    if (!this.pendingPattern) {
      this.pendingPattern = pattern;
      this.pinError = '';
      return;
    }
    if (pattern !== this.pendingPattern) {
      this.pendingPattern = '';
      this.pinError = '两次图案不一致，请重画';
      return;
    }
    await this.store.setVaultPattern(pattern);
    await this.store.hideFolderToVault(this.source.id, this.pendingHideEntry.path, this.pendingHideEntry.name);
    this.pendingHideEntry = null;
    this.pendingPattern = '';
    this.pinError = '';
  }

  private findSiblingSubtitleUrl(videoEntry: RemoteFileEntry): string {
    const base = Formatters.stripExtension(videoEntry.name).toLowerCase();
    for (let i = 0; i < this.entries.length; i++) {
      const e = this.entries[i];
      if (!e.isSubtitle) continue;
      const subBase = Formatters.stripExtension(e.name).toLowerCase();
      if (subBase === base || subBase.startsWith(base)) {
        return e.fullUrl;
      }
    }
    return '';
  }

  private async openOrPlayEntry(entry: RemoteFileEntry, directPlay: boolean): Promise<void> {
    if (!this.source) return;
    if (entry.isDirectory) {
      this.loadDirectory(entry.path, true);
      return;
    }
    if (!entry.isVideo) return;
    const subUrl = this.findSiblingSubtitleUrl(entry);
    const item: MediaItem = await this.store.addRemoteFileToLibrary(this.source, entry, subUrl);
    if (directPlay) {
      const launch: PlayerLaunchParams = {
        item,
        source: this.source,
        startPositionMs: 0
      };
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PlayerPage', params: launch });
    } else {
      const detail: MediaDetailParams = { movie: item };
      this.getUIContext().getRouter().pushUrl({ url: 'pages/MediaDetailPage', params: detail });
    }
  }

  @Builder
  filterPill(label: string, mode: BrowserFilter) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.filterMode === mode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.filterMode === mode ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(14)
      .backgroundColor(this.filterMode === mode ? $r('app.color.accent_blue') : $r('app.color.bg_elevated'))
      .border({ width: 0.7, color: this.filterMode === mode ? $r('app.color.accent_blue') : $r('app.color.border_subtle') })
      .onClick(() => { this.filterMode = mode; })
  }

  build() {
    Column() {
      NavHeaderBar({
        title: this.source ? this.source.name : '远程目录',
        subtitle: this.currentDirPath,
        rightIcon: $r('sys.symbol.arrow_clockwise'),
        onBack: () => this.navigateBackOneLevel(),
        onRightAction: () => this.loadDirectory(this.currentDirPath, false)
      })

      Refresh({ refreshing: this.refreshing }) {
      Stack() {
        PageShell({ maxWidth: 1100 }) {
          Stack({ alignContent: Alignment.Top }) {
            Column() {

              // Interactive Scrollable Breadcrumb Trail
              Scroll() {
                Row({ space: 6 }) {
                  ForEach(this.getBreadcrumbs(), (crumb: BreadcrumbSegment, idx: number) => {
                    Row({ space: 6 }) {
                      if (idx > 0) {
                        SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(11)
                        .fontColor([$r('app.color.text_muted')])
                      }
                      Text(crumb.label)
                      .fontSize(12)
                      .fontWeight(idx === this.getBreadcrumbs().length - 1 ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(idx === this.getBreadcrumbs().length - 1 ? $r('app.color.accent_cyan') : $r('app.color.text_secondary'))
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .borderRadius(7)
                      .backgroundColor(idx === this.getBreadcrumbs().length - 1 ? '#1F38BDF8' : $r('app.color.bg_elevated'))
                      .onClick(() => {
                        if (crumb.path !== this.currentDirPath) {
                          this.pathHistory = this.getBreadcrumbs().slice(0, idx).map(c => c.path);
                          this.loadDirectory(crumb.path, false);
                        }
                      })
                    }
                  }, (c: BreadcrumbSegment) => `${c.path}_${c.label}`)
                }
                .padding({ left: 18, right: 18, top: 10, bottom: 6 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .align(Alignment.TopStart)
              .scrollBar(BarState.Off)
              .width('100%')

              if (this.source && this.source.type === 'youtube') {
                Row({ space: 8 }) {
                  TextInput({ text: this.ytSearchQuery, placeholder: '搜索 YouTube 视频或输入关键词...' })
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_elevated'))
                  .borderRadius(10)
                  .onChange((v: string) => { this.ytSearchQuery = v; })
                  .onSubmit(() => {
                    const q = this.ytSearchQuery.trim();
                    if (q) this.loadDirectory(`/search?q=${q}`, true);
                  })
                  Button('搜索')
                  .height(38)
                  .padding({ left: 14, right: 14 })
                  .fontSize(12)
                  .fontColor(Color.White)
                  .backgroundColor($r('app.color.accent_blue'))
                  .borderRadius(10)
                  .onClick(() => {
                    const q = this.ytSearchQuery.trim();
                    if (q) this.loadDirectory(`/search?q=${q}`, true);
                  })
                }
                .width('100%')
                .padding({ left: 18, right: 18, top: 4, bottom: 6 })
              }

              // Filter + Quick Close to Sources Row
              Row({ space: 8 }) {
                this.filterPill('全部', 'all')
                this.filterPill('视频', 'video')
                this.filterPill('字幕', 'subtitle')
                Blank()
                Text(`${this.getFilteredEntries().length} 项`)
                .fontSize(11)
                .fontColor($r('app.color.text_muted'))
                if (this.pathHistory.length > 0) {
                  Text('关闭')
                  .fontSize(12)
                  .fontColor($r('app.color.accent_blue'))
                  .padding({ left: 8, right: 4 })
                  .onClick(() => this.getUIContext().getRouter().back())
                }
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 4, bottom: 10 })

              if (this.loading) {
                Column({ space: 10 }) {
                  LoadingProgress().width(36).height(36).color($r('app.color.accent_blue'))
                  Text('正在读取目录与片源列表...').fontSize(13).fontColor($r('app.color.text_muted'))
                }
                .width('100%')
                .padding({ top: 72 })
              } else if (this.errorText) {
                Column({ space: 12 }) {
                  Column() {
                    SymbolGlyph($r('sys.symbol.exclamationmark_circle_fill'))
                    .fontSize(26)
                    .fontColor([$r('app.color.warning')])
                  }
                  .width(52)
                  .height(52)
                  .borderRadius(26)
                  .backgroundColor('#22FBBF24')
                  .justifyContent(FlexAlign.Center)

                  Text('暂时无法打开目录')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))

                  Text(Formatters.toFriendlyError(this.errorText))
                  .fontSize(13)
                  .lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center)
                  .constraintSize({ maxWidth: 340 })

                  Row({ space: 10 }) {
                    Button('重新加载')
                    .height(38)
                    .padding({ left: 18, right: 18 })
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .backgroundColor($r('app.color.accent_blue'))
                    .borderRadius(10)
                    .onClick(() => this.loadDirectory(this.currentDirPath, false))
                    Button('返回片源')
                    .height(38)
                    .padding({ left: 16, right: 16 })
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.bg_elevated'))
                    .borderRadius(10)
                    .border({ width: 0.7, color: $r('app.color.fill_strong') })
                    .onClick(() => this.getUIContext().getRouter().back())
                  }
                }
                .width('100%')
                .padding({ left: 28, right: 28, top: 60 })
              } else if (this.getFilteredEntries().length === 0) {
                Column({ space: 10 }) {
                  Image($r('app.media.ic_file_folder')).width(44).height(44)
                  Text('当前目录无可匹配条目')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ top: 64 })
              } else {
                List({ space: 8 }) {
                  ForEach(this.getFilteredEntries(), (entry: RemoteFileEntry) => {
                    ListItem() {
                      Row({ space: 12 }) {
                        Column() {
                          Image(MediaArtwork.fileEntryIcon(entry))
                          .width(24)
                          .height(24)
                        }
                        .width(40)
                        .height(40)
                        .borderRadius(10)
                        .backgroundColor($r('app.color.bg_secondary'))
                        .justifyContent(FlexAlign.Center)

                        Column({ space: 3 }) {
                          Text(entry.name)
                          .fontSize(14)
                          .fontWeight(entry.isVideo || entry.isDirectory ? FontWeight.Medium : FontWeight.Normal)
                          .fontColor(entry.isVideo || entry.isDirectory ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Row({ space: 8 }) {
                            if (entry.isDirectory) {
                              Text(entry.lastModified || '文件夹').fontSize(11).fontColor($r('app.color.text_muted'))
                            } else {
                              Text(
                              entry.size > 0
                              ? Formatters.formatBytes(entry.size)
                              : (entry.lastModified || '网络流媒体')
                              ).fontSize(11).fontColor($r('app.color.text_muted'))
                              if (entry.isSubtitle) {
                                Text('外挂字幕').fontSize(10).fontColor($r('app.color.success'))
                              } else if (entry.name.toLowerCase().endsWith('.nfo')) {
                                Text('NFO 元数据').fontSize(10).fontColor($r('app.color.accent_cyan'))
                              } else if (entry.isVideo && this.findSiblingSubtitleUrl(entry)) {
                                Text('已匹配字幕').fontSize(10).fontColor($r('app.color.success'))
                              }
                            }
                          }
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)

                        if (entry.isVideo) {
                          Row({ space: 6 }) {
                            Button() {
                              Row({ space: 4 }) {
                                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(11).fontColor([Color.White])
                                Text('播放').fontSize(12).fontColor(Color.White)
                              }
                            }
                            .height(32)
                            .padding({ left: 10, right: 11 })
                            .backgroundColor($r('app.color.accent_blue'))
                            .borderRadius(8)
                            .onClick(() => this.openOrPlayEntry(entry, true))

                            Button() {
                              SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(14).fontColor([$r('app.color.text_primary')])
                            }
                            .width(32)
                            .height(32)
                            .backgroundColor($r('app.color.bg_secondary'))
                            .borderRadius(8)
                            .border({ width: 0.6, color: $r('app.color.fill_strong') })
                            .onClick(() => this.saveEntryVideoOffline(entry))
                          }
                        } else if (entry.isDirectory) {
                          if (this.source && this.store.isPathRuleHidden(this.source.id, entry.path)) {
                            Image($r('app.media.ic_lock_vault')).width(16).height(16)
                          }
                          Button({ type: ButtonType.Circle }) {
                            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                            .fontSize(17)
                            .fontColor([$r('app.color.text_secondary')])
                          }
                          .width(30)
                          .height(30)
                          .backgroundColor($r('app.color.bg_secondary'))
                          .bindMenu([
                          {
                            value: '打开目录',
                            action: () => this.openOrPlayEntry(entry, false)
                          },
                          {
                            value: (this.source && this.store.isPathRuleHidden(this.source.id, entry.path))
                            ? '取消隐藏'
                            : '隐藏到保险库（整个目录）',
                            action: () => this.requestHideFolder(entry)
                          }
                          ])
                        }
                      }
                      .width('100%')
                      .padding(12)
                      .borderRadius(12)
                      .backgroundColor($r('app.color.bg_elevated'))
                      .border({ width: 0.8, color: $r('app.color.fill_strong') })
                      .onClick(() => this.openOrPlayEntry(entry, true))
                    }
                  }, (entry: RemoteFileEntry) => entry.path)
                }
                .layoutWeight(1)
                .width('100%')
                .padding({ left: 18, right: 18, bottom: 20 })
              }
            }
            .width('100%')
            .height('100%')

            if (this.pendingHideEntry) {
              Stack({ alignContent: Alignment.Top }) {
                Column()
                .width('100%')
                .height('100%')
                .backgroundColor($r('app.color.scrim_backdrop'))
                .onClick(() => { this.pendingHideEntry = null; })

                Column({ space: 10 }) {
                  Text('设置解锁图案')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  Text(`将隐藏「${this.pendingHideEntry.name}」`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.pendingPattern ? '再次绘制确认' : '绘制图案（至少 4 点）')
                  .fontSize(12)
                  .fontColor($r('app.color.text_muted'))
                  PatternPad({
                    padSize: 230,
                    onComplete: (pattern: string) => { this.onPattern(pattern); },
                    onInvalid: (message: string) => { this.pinError = message; }
                  })
                  if (this.pinError) {
                    Text(this.pinError)
                    .fontSize(11)
                    .fontColor($r('app.color.danger'))
                  }
                  Button('取消')
                  .width('100%')
                  .height(38)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(9)
                  .onClick(() => { this.pendingHideEntry = null; })
                }
                .width('90%')
                .constraintSize({ maxWidth: 380 })
                .padding(18)
                .margin({ top: 80 })
                .borderRadius(16)
                .backgroundColor($r('app.color.bg_elevated'))
                .border({ width: 1, color: '#55F5B841' })
                .shadow({ radius: 24, color: '#CC000000', offsetX: 0, offsetY: 8 })
              }
              .width('100%')
              .height('100%')
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_primary'))
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
      }
      .width('100%')
      .layoutWeight(1)
      .onRefreshing(async () => {
        this.refreshing = true;
        if (!this.loading) {
          await this.loadDirectory(this.currentDirPath, false);
        }
        this.refreshing = false;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

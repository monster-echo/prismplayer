import { BreakpointType } from '../common/Constants';
import { Layout } from '../common/Layout';
import { MediaArtwork } from '../common/MediaArtwork';
import { appMenuOptions } from '../common/MenuSurface';
import { MediaItem, MediaSource, PlayerLaunchParams } from '../common/Types';
import { AppStore } from '../services/AppStore';
import { RemoteSourceClient } from '../services/RemoteSourceClient';

@ComponentV2
export struct SourcesView {
  @Param breakpoint: BreakpointType = 'sm';
  @Param contentWidth: number = 360;
  @Param onOpenEditor: (editing: MediaSource | null) => void = () => {};
  @Param onBrowseSource: (source: MediaSource) => void = () => {};
  @Param onRequestPro: () => void = () => {};
  @Param onPlayItem: (item: MediaItem, startPosMs: number) => void = () => {};

  @Local store: AppStore = AppStore.getInstance();
  @Local probeStatusMap: Record<string, string> = {};
  @Local probingSourceId: string = '';
  @Local refreshing: boolean = false;
  private async runQuickProbe(src: MediaSource): Promise<void> {
    this.probingSourceId = src.id;
    const next: Record<string, string> = {};
    const keys = Object.keys(this.probeStatusMap);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = this.probeStatusMap[keys[i]];
    }
    next[src.id] = '正在测速检测...';
    this.probeStatusMap = next;

    const res = await RemoteSourceClient.testConnection(src);
    const updated: Record<string, string> = {};
    const updatedKeys = Object.keys(this.probeStatusMap);
    for (let i = 0; i < updatedKeys.length; i++) {
      updated[updatedKeys[i]] = this.probeStatusMap[updatedKeys[i]];
    }
    updated[src.id] = res.ok ? `✓ ${res.latencyMs}ms · ${res.message}` : `✕ ${res.message}`;
    this.probeStatusMap = updated;
    this.probingSourceId = '';
  }

  private confirmDeleteSource(src: MediaSource): void {
    this.getUIContext().showAlertDialog({
      title: `移除片源「${src.name}」`,
      message: '将清除该片源从影库刮削的索引和观看记录，不会影响服务器上的原始视频文件。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认移除',
        fontColor: $r('app.color.danger'),
        action: () => { this.store.deleteSource(src.id); }
      }
    });
  }

  build() {
    Column() {
        // Sleek Single-Line Header + Unified Add Source Menu（固定 header）
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text('片源管理')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('本地 · WebDAV · SMB · Plex · 链接')
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button() {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(14)
                .fontColor([Color.White])
              Text('添加片源')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
          }
          .height(38)
          .padding({ left: 13, right: 15 })
          .backgroundColor($r('app.color.accent_blue'))
          .borderRadius(10)
          .bindMenu([
            {
              value: '粘贴视频链接（尝试播放）',
              action: () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/OnlineMediaPage' });
              }
            },
            {
              value: '连接网络 / 云存储 / NAS',
              action: () => {
                if (!this.store.canAddSource()) {
                  this.onRequestPro();
                  return;
                }
                this.onOpenEditor(null);
              }
            },
            {
              value: '导入手机或本地视频',
              action: () => { this.store.importLocalVideos(); }
            }
          ], appMenuOptions())
        }
        .padding({
          left: Layout.gutter(this.breakpoint),
          right: Layout.gutter(this.breakpoint),
          top: 16
        })
        .width('100%')

        Refresh({ refreshing: this.refreshing }) {
        Scroll() {
          Column({ space: 18 }) {
        if (this.store.scanStatusText) {
          Row({ space: 8 }) {
            if (this.store.isScanning) {
              LoadingProgress().width(16).height(16).color($r('app.color.accent_blue'))
            } else {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(15).fontColor([$r('app.color.success')])
            }
            Text(this.store.scanStatusText)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.7, color: $r('app.color.fill_strong') })
        }

        if (this.store.sources.length === 0) {
          Column({ space: 16 }) {
            Row({ space: 14 }) {
              Image($r('app.media.ic_cloud_alist')).width(36).height(36)
              Image($r('app.media.ic_nas_synology')).width(36).height(36)
              Image($r('app.media.ic_nas_fnos')).width(36).height(36)
              Image($r('app.media.ic_nas_qnap')).width(36).height(36)
            }
            Text('尚未连接私有云或网盘片源')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('支持群晖 Synology、飞牛 fnOS、威联通 QNAP、Alist / OpenList（阿里云盘 / 夸克 / 115）直连流播，不占用设备本地存储')
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_muted'))
              .textAlign(TextAlign.Center)
              .constraintSize({ maxWidth: 440 })

            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.plus')).fontSize(14).fontColor([Color.White])
                Text('立即连接 NAS / Alist').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
              }
            }
            .height(40)
            .padding({ left: 18, right: 18 })
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(10)
            .onClick(() => this.onOpenEditor(null))
          }
          .width('100%')
          .constraintSize({ maxWidth: 640 })
          .alignSelf(ItemAlign.Center)
          .padding(32)
          .borderRadius(16)
          .backgroundColor($r('app.color.bg_elevated'))
          .border({ width: 0.8, color: $r('app.color.fill_strong') })
        } else {
          Grid() {
            ForEach(this.store.sources, (src: MediaSource) => {
              GridItem() {
              Column({ space: 12 }) {
                Row({ space: 12 }) {
                  Column() {
                    Image(MediaArtwork.sourceIcon(src))
                      .width(28)
                      .height(28)
                  }
                  .width(48)
                  .height(48)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.fill_subtle'))
                  .border({ width: 0.6, color: $r('app.color.fill_strong') })
                  .justifyContent(FlexAlign.Center)

                  Column({ space: 3 }) {
                    Row({ space: 8 }) {
                      Text(src.name)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text(MediaArtwork.sourceBadgeLabel(src))
                        .fontSize(10)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.accent_cyan'))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(5)
                        .backgroundColor('#2238BDF8')
                    }
                    Text(`${src.baseUrl}${src.rootPath && src.rootPath !== '/' ? src.rootPath : ''}`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_muted'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(
                      this.probeStatusMap[src.id]
                        ? this.probeStatusMap[src.id]
                        : `已入库 ${this.store.sourceItemCount(src.id)} 项 · ${src.lastScannedAt > 0 ? '已刮削同步' : '待扫描刮削'}`
                    )
                      .fontSize(11)
                      .fontColor(
                        this.probeStatusMap[src.id]?.startsWith('✓')
                          ? $r('app.color.success')
                          : (this.probeStatusMap[src.id]?.startsWith('✕') ? $r('app.color.danger') : $r('app.color.text_secondary'))
                      )
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(15)
                    .fontColor([$r('app.color.text_muted')])
                }
                .width('100%')
                .onClick(() => this.onBrowseSource(src))

                Row({ space: 8 }) {
                  Button() {
                    Row({ space: 5 }) {
                      SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(13).fontColor([Color.White])
                      Text('浏览目录').fontSize(12).fontColor(Color.White)
                    }
                  }
                  .height(34)
                  .padding({ left: 13, right: 14 })
                  .backgroundColor($r('app.color.accent_blue'))
                  .borderRadius(8)
                  .onClick(() => this.onBrowseSource(src))

                  Button() {
                    Row({ space: 5 }) {
                      SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([$r('app.color.text_primary')])
                      Text(this.store.isScanning ? '刮削中...' : '扫描刮削').fontSize(12).fontColor($r('app.color.text_primary'))
                    }
                  }
                  .height(34)
                  .padding({ left: 12, right: 14 })
                  .backgroundColor($r('app.color.bg_secondary'))
                  .borderRadius(8)
                  .enabled(!this.store.isScanning)
                  .onClick(() => { this.store.scanSource(src); })

                  Blank()

                  // Fold secondary actions (Health Check, Edit, Clear Index, Delete) into clean submenu
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                      .fontSize(18)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width(34)
                  .height(34)
                  .backgroundColor($r('app.color.bg_secondary'))
                  .bindMenu([
                    {
                      value: this.probingSourceId === src.id ? '测速中...' : '测试连通性与延迟',
                      action: () => { this.runQuickProbe(src); }
                    },
                    {
                      value: '编辑连接配置',
                      action: () => this.onOpenEditor(src)
                    },
                    {
                      value: '清理该源本地索引',
                      action: () => { this.store.clearSourceIndex(src.id); }
                    },
                    {
                      value: '移除此片源',
                      action: () => this.confirmDeleteSource(src)
                    }
                  ], appMenuOptions())
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .borderRadius(14)
              .backgroundColor($r('app.color.bg_elevated'))
              .border({ width: 0.8, color: $r('app.color.fill_strong') })
              }
            }, (src: MediaSource) => src.id)
          }
          .columnsTemplate(this.contentWidth >= 860 ? '1fr 1fr' : '1fr')
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
        }
      }
      .padding({
        left: Layout.gutter(this.breakpoint),
        right: Layout.gutter(this.breakpoint),
        top: 16,
        bottom: 32
      })
      .width('100%')
      .constraintSize({ maxWidth: Layout.contentMax(this.breakpoint) + Layout.gutter(this.breakpoint) * 2 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .width('100%')
    .onRefreshing(async () => {
      this.refreshing = true;
      await this.store.reloadAllData();
      this.refreshing = false;
    })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

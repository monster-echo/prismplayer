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

  private confirmClearLocal(): void {
    this.getUIContext().showAlertDialog({
      title: '清空本机影库条目',
      message: '只清理索引与观看记录，不会删除本机文件；重新扫描即可恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger'),
        action: () => { this.store.clearLocalLibrary(); }
      }
    });
  }

  /** 本机片源还没选目录时，「浏览」先引导选文件夹，避免打开空目录。 */
  private openOrPickFolder(src: MediaSource): void {
    if (src.type === 'local' && !src.rootPath) {
      this.store.pickLocalMedia();
      return;
    }
    this.onBrowseSource(src);
  }

  private confirmDeleteSource(src: MediaSource): void {
    this.getUIContext().showAlertDialog({
      title: `移除片源「${src.name}」`,
      message: '会移除该片源在影库中的条目与观看记录，不影响服务器上的文件。',
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
          Text('片源管理')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .alignSelf(ItemAlign.Start)

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
              value: '添加 NAS / 网盘',
              action: () => {
                if (!this.store.canAddSource()) {
                  this.onRequestPro();
                  return;
                }
                this.onOpenEditor(null);
              }
            },
            {
              value: '粘贴视频链接',
              action: () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/OnlineMediaPage' });
              }
            },
            {
              value: '从相册导入视频',
              action: () => { this.store.importFromGallery(); }
            },
            {
              value: '导入文件（视频 / 音乐）',
              action: () => { this.store.importLocalVideos(); }
            },
            {
              value: '添加本机视频 / 文件夹',
              action: () => { this.store.pickLocalMedia(); }
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
          Column({ space: 14 }) {
            Text('还没有片源')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('群晖 · 飞牛 · 威联通 · Alist · Plex · SMB · 本机存储')
              .fontSize(12)
              .fontColor($r('app.color.text_body_muted'))
              .textAlign(TextAlign.Center)

            Row({ space: 10 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.plus')).fontSize(14).fontColor([Color.White])
                  Text('连接 NAS / Alist').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
                }
              }
              .height(40)
              .padding({ left: 18, right: 18 })
              .backgroundColor($r('app.color.accent_blue'))
              .borderRadius(10)
              .onClick(() => this.onOpenEditor(null))

              Button('添加本机视频')
                .height(40)
                .padding({ left: 16, right: 16 })
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.bg_secondary'))
                .borderRadius(10)
                .border({ width: 0.7, color: $r('app.color.fill_strong') })
                .onClick(() => { this.store.pickLocalMedia(); })
            }
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
                    Text(MediaArtwork.sourceSubtitle(src))
                      .fontSize(12)
                      .fontColor($r('app.color.text_body_muted'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(
                      this.probeStatusMap[src.id]
                        ? this.probeStatusMap[src.id]
                        : (src.type === 'local' && !src.rootPath
                          ? '支持视频 / 音乐 / 字幕'
                          : `${this.store.sourceItemCount(src.id)} 项 · ${src.lastScannedAt > 0 ? (src.type === 'local' ? '已索引' : '已同步') : '未扫描'}`)
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

                  Image($r('app.media.ic_chevron_right'))
                    .width(16)
                    .height(16)
                    .fillColor($r('app.color.text_muted'))
                }
                .width('100%')
                .onClick(() => this.openOrPickFolder(src))

                Row({ space: 8 }) {
                  Button() {
                    Row({ space: 5 }) {
                      SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(13).fontColor([Color.White])
                      Text(src.type === 'local' && !src.rootPath ? '添加视频' : '浏览').fontSize(12).fontColor(Color.White)
                    }
                  }
                  .height(34)
                  .padding({ left: 13, right: 14 })
                  .backgroundColor($r('app.color.accent_blue'))
                  .borderRadius(8)
                  .onClick(() => this.openOrPickFolder(src))

                  if (!(src.type === 'local' && !src.rootPath)) {
                    Button() {
                      Row({ space: 5 }) {
                        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([$r('app.color.text_primary')])
                        Text(this.store.isScanning ? '扫描中...' : '扫描').fontSize(12).fontColor($r('app.color.text_primary'))
                      }
                    }
                    .height(34)
                    .padding({ left: 12, right: 14 })
                    .backgroundColor($r('app.color.bg_secondary'))
                    .borderRadius(8)
                    .enabled(!this.store.isScanning)
                    .onClick(() => { this.store.scanSource(src); })
                  }

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
                  .bindMenu(src.type === 'local' ? [
                    {
                      value: src.rootPath ? '更换本机文件夹' : '添加本机视频 / 文件夹',
                      action: () => { this.store.pickLocalMedia(); }
                    },
                    {
                      value: this.probingSourceId === src.id ? '检测中...' : '检测授权是否有效',
                      action: () => { this.runQuickProbe(src); }
                    },
                    {
                      value: '清理本机影库索引',
                      action: () => { this.store.clearSourceIndex(src.id); }
                    },
                    {
                      value: '清空本机影库条目',
                      action: () => this.confirmClearLocal()
                    }
                  ] : [
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
    }.edgeEffect(EdgeEffect.Spring)
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

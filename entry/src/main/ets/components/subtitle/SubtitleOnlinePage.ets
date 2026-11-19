import { SUBTITLE_SEARCH_LANGUAGES, SubtitleSearchLanguage } from '../../common/Types';
import { OnlineSubtitleResult } from '../../services/SubtitleService';
import { SubtitleSession } from '../../services/SubtitleSession';
import {
  SubtitleChip,
  SubtitlePageHeader,
  SubtitleSectionHeader,
  SubtitleToast
} from './SubtitleUi';

/**
 * One responsibility: find and mount an online subtitle for the current video.
 * Searching, judging candidates and downloading are intentionally one screen;
 * playback styling and timing live elsewhere.
 */
@ComponentV2
export struct SubtitleOnlinePage {
  @Local session: SubtitleSession = SubtitleSession.getInstance();
  @Local mountingId: string = '';
  @Param onBack: () => void = () => {};
  @Param onClose: () => void = () => {};

  private async runSearch(): Promise<void> {
    const query = this.session.onlineQuery.trim();
    if (!query) {
      SubtitleToast.show(this.getUIContext(), '请先输入片名或英文名');
      return;
    }
    try {
      const count = await this.session.searchOnline(query);
      if (count === 0) {
        SubtitleToast.show(this.getUIContext(), '未找到匹配字幕，可尝试英文片名或更换语言');
      }
    } catch (e) {
      SubtitleToast.show(this.getUIContext(), e instanceof Error ? e.message : '在线字幕搜索失败');
    }
  }

  private async runAutoMatch(): Promise<void> {
    try {
      const result = await this.session.autoMatchOnline();
      if (result) {
        const suffix = this.session.onlineFuzzyFallback ? '（同剧其他集，请核对季集）' : '';
        SubtitleToast.show(this.getUIContext(), `已自动加载 ${result.langLabel} 字幕${suffix}`);
      } else {
        SubtitleToast.show(this.getUIContext(), '未找到可匹配的在线字幕，可手动搜索');
      }
    } catch (e) {
      SubtitleToast.show(this.getUIContext(), e instanceof Error ? e.message : '自动匹配失败');
    }
  }

  private fileName(): string {
    const item = this.session.mediaItem;
    return item && item.fileName ? item.fileName : '未知文件名';
  }

  private resetToFileName(): void {
    this.session.resetOnlineQueryToMedia();
    SubtitleToast.show(this.getUIContext(), '已按文件名重置搜索词');
  }

  private primaryLanguages(): SubtitleSearchLanguage[] {
    return SUBTITLE_SEARCH_LANGUAGES.slice(0, 4);
  }

  private secondaryLanguages(): SubtitleSearchLanguage[] {
    return SUBTITLE_SEARCH_LANGUAGES.slice(4);
  }

  private async mount(result: OnlineSubtitleResult): Promise<void> {
    if (this.mountingId) return;
    this.mountingId = result.id;
    try {
      await this.session.mountOnlineSubtitle(result);
      SubtitleToast.show(this.getUIContext(), `已加载 ${result.langLabel} 字幕`);
    } catch (e) {
      SubtitleToast.show(this.getUIContext(), e instanceof Error ? e.message : '在线字幕加载失败');
    } finally {
      this.mountingId = '';
    }
  }

  @Builder
  resultRow(result: OnlineSubtitleResult) {
    Row({ space: 8 }) {
      Text(result.langLabel)
        .fontSize(10)
        .fontColor('#3B82F6')
        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor('#1E3B82F6')
      Column({ space: 2 }) {
        Text(result.title)
          .fontSize(12)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${result.sourceName} · ${result.format}`)
          .fontSize(10)
          .fontColor('#6B7280')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.mountingId === result.id) {
        LoadingProgress().width(16).height(16).color('#3B82F6')
      } else {
        Text('加载')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#93C5FD')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor('#1A3B82F6')
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .borderRadius(9)
    .backgroundColor('#101218')
    .onClick(() => {
      if (!this.mountingId) this.mount(result);
    })
  }

  build() {
    Column() {
      SubtitlePageHeader({
        title: '在线字幕',
        caption: 'SubDL · OpenSubtitles · 字幕库聚合搜索',
        onBack: () => this.onBack(),
        onClose: () => this.onClose()
      })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            SubtitleSectionHeader({
              title: '搜索在线字幕',
              note: '搜索词取文件名中的片名；季集用于结果优先排序'
            })

            Row({ space: 6 }) {
              Text('当前文件')
                .fontSize(10)
                .fontColor('#6B7280')
              Text(this.fileName())
                .fontSize(10)
                .fontColor('#94A3B8')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('按文件名重置')
                .fontSize(10)
                .fontColor('#93C5FD')
                .onClick(() => this.resetToFileName())
            }
            .width('100%')
            .padding({ left: 9, right: 9, top: 7, bottom: 7 })
            .borderRadius(8)
            .backgroundColor('#101218')

            if (this.session.mediaMatchScopeLabel()) {
              Row({ space: 6 }) {
                Text('按季集优先').fontSize(10).fontColor('#6B7280')
                Text(this.session.mediaMatchScopeLabel())
                  .fontSize(10)
                  .fontColor('#93C5FD')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(5)
                  .backgroundColor('#1A3B82F6')
                Text('同季集命中会排在前面').fontSize(10).fontColor('#6B7280')
              }
              .width('100%')
            }

            Row({ space: 8 }) {
              TextInput({ text: this.session.onlineQuery, placeholder: '片名，如 the last of us' })
                .layoutWeight(1)
                .height(40)
                .fontSize(13)
                .fontColor(Color.White)
                .placeholderColor('#6B7280')
                .backgroundColor('#101218')
                .borderRadius(10)
                .border({ width: 0.7, color: '#1FFFFFFF' })
                .onChange((v: string) => this.session.setOnlineQuery(v))
                .onSubmit(() => this.runSearch())
              Button(this.session.onlineSearching ? '搜索中' : '搜索')
                .height(40)
                .padding({ left: 16, right: 16 })
                .fontSize(13)
                .fontColor(Color.White)
                .backgroundColor(this.session.onlineSearching ? '#1F3B82F6' : '#3B82F6')
                .borderRadius(10)
                .enabled(!this.session.onlineSearching)
                .onClick(() => this.runSearch())
            }
            .width('100%')

            Button() {
              Row({ space: 7 }) {
                if (this.session.autoMatching) {
                  LoadingProgress().width(15).height(15).color(Color.White)
                } else {
                  SymbolGlyph($r('sys.symbol.wand_and_stars_fill'))
                    .fontSize(15)
                    .fontColor([Color.White])
                }
                Text(this.session.autoMatching ? '正在匹配...' : '自动匹配最佳字幕')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
              }
            }
            .width('100%')
            .height(42)
            .backgroundColor('#1F3B82F6')
            .border({ width: 0.8, color: '#553B82F6' })
            .borderRadius(10)
            .enabled(!this.session.autoMatching && !this.session.onlineSearching)
            .onClick(() => this.runAutoMatch())

            Divider().color('#1FFFFFFF')

            SubtitleSectionHeader({
              title: '字幕语言',
              note: '国际源按语言筛选；字幕库为中文站，重新搜索后生效'
            })
            Row({ space: 8 }) {
              ForEach(this.primaryLanguages(), (opt: SubtitleSearchLanguage) => {
                SubtitleChip({
                  label: opt.label,
                  active: this.session.languageFilter === opt.code,
                  onTap: () => this.session.setLanguageFilter(opt.code)
                })
              }, (opt: SubtitleSearchLanguage) => `lang_${opt.code}_${this.session.languageFilter === opt.code}`)
            }
            .width('100%')
            Row({ space: 8 }) {
              ForEach(this.secondaryLanguages(), (opt: SubtitleSearchLanguage) => {
                SubtitleChip({
                  label: opt.label,
                  active: this.session.languageFilter === opt.code,
                  onTap: () => this.session.setLanguageFilter(opt.code)
                })
              }, (opt: SubtitleSearchLanguage) => `lang2_${opt.code}_${this.session.languageFilter === opt.code}`)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            SubtitleSectionHeader({
              title: `候选字幕（${this.session.onlineResults.length}）`,
              note: '点击即下载并挂载，自动开启外挂字幕'
            })
            if (this.session.onlineFuzzyFallback && this.session.onlineResults.length > 0) {
              Text(`未找到 ${this.session.mediaMatchScopeLabel()} 的精确字幕，以下为同剧其他结果，加载前请核对季集。`)
                .fontSize(11)
                .lineHeight(17)
                .fontColor('#F59E0B')
                .width('100%')
                .padding(10)
                .borderRadius(8)
                .backgroundColor('#1AF59E0B')
            }
            if (this.session.onlineResults.length === 0) {
              Text(this.session.onlineSearching ? '正在搜索...' : '还没有候选；先搜索或自动匹配')
                .fontSize(12)
                .fontColor('#6B7280')
                .padding({ top: 4, bottom: 4 })
            } else {
              ForEach(this.session.onlineResults, (result: OnlineSubtitleResult) => {
                this.resultRow(result)
              }, (result: OnlineSubtitleResult) => `online_${result.id}_${this.mountingId === result.id}`)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor('#14161D')
          .border({ width: 0.7, color: '#1FFFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Text('在线字幕来自第三方公开源，加载前请确认视频标题与季集信息；RAR 压缩包暂不支持。')
            .fontSize(10)
            .lineHeight(16)
            .fontColor('#6B7280')
            .padding({ left: 4, right: 4 })
        }
        .padding({ left: 18, right: 18, top: 8, bottom: 36 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF0B0D12')
  }
}

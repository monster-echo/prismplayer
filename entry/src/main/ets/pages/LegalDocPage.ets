import { AppConstants } from '../common/Constants';
import { LegalDocParams } from '../common/Types';
import { NavHeaderBar } from '../components/NavHeaderBar';

interface LegalSection {
  title: string;
  paragraphs: string[];
}

@Entry
@ComponentV2
struct LegalDocPage {
  @Local docType: string = 'privacy';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as LegalDocParams | undefined;
    if (params && params.docType === 'agreement') {
      this.docType = 'agreement';
    }
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private get docTitle(): string {
    return this.docType === 'agreement' ? '用户服务协议' : '隐私政策';
  }

  private get docSubtitle(): string {
    if (this.docType === 'agreement') {
      return `生效日期：${AppConstants.POLICY_UPDATED_DATE}`;
    }
    return `更新日期：${AppConstants.POLICY_UPDATED_DATE} · 生效即适用`;
  }

  /** 《隐私政策》：面向"本地优先、零上传"架构的标准披露结构。 */
  private get privacySections(): LegalSection[] {
    return [
      {
        title: '引言',
        paragraphs: [
          '棱镜影院 PrismPlayer（以下简称"本应用"）由开发者（以下简称"我们"）提供。本应用是一款运行于 HarmonyOS 的本地与私有云影音播放工具，我们高度重视并全力保护您的个人信息与隐私安全。',
          '请您在使用本应用前仔细阅读本政策。您点击"同意并继续"或实际使用本应用，即表示您已理解并同意本政策的全部内容。'
        ]
      },
      {
        title: '一、我们收集和使用您的个人信息的情况',
        paragraphs: [
          '1. 本应用不要求注册账号，不收集您的姓名、手机号、身份证件、位置、通讯录、相册等任何个人身份信息，也不含任何广告或数据统计 SDK，不会将任何个人信息上传至我们的服务器（本应用亦不运营任何自有服务器）。',
          '2. 本地数据：您添加的片源地址与凭据、影库信息、播放历史、播放偏好设置等数据，仅保存在您的设备本地，用于为您提供播放与影库功能。',
          '3. 片源访问：当您主动添加并访问 WebDAV / SMB / Alist / Emby / Plex 等您自有的媒体服务器时，本应用仅与您指定的服务器地址通信，凭据经系统硬件级密钥库加密后存储于本机。',
          '4. TMDB 海报刮削：仅在您主动配置 TMDB API Key 并开启刮削时，本应用会向 TMDB（api.themoviedb.org）发送影片名称查询请求，请求内容不包含任何用户身份信息。关闭该功能即不产生任何此类请求。'
        ]
      },
      {
        title: '二、权限使用说明',
        paragraphs: [
          '1. 网络权限（ohos.permission.INTERNET）：仅在您主动访问已配置的媒体源、启用 TMDB 刮削或访问在线直链时使用。',
          '2. 网络状态权限（ohos.permission.GET_NETWORK_INFO）：用于判断网络连接状态以优化流媒体传输策略，不涉及任何个人身份信息。',
          '3. 本应用不申请定位、相机、麦克风、通讯录、存储敏感区等任何其他权限。'
        ]
      },
      {
        title: '三、第三方服务与组件披露',
        paragraphs: [
          '1. 华为 IAP Kit（华为应用内支付）：当您主动购买 Pro 买断权益时使用。订单创建与支付流程由华为公司按照其隐私政策处理，我们不获取您的支付账号信息，仅在本机保存权益激活状态。',
          '2. TMDB（The Movie Database）：仅在您主动配置并启用刮削时按需访问，详见本政策第一条第 4 款。',
          '3. 本地开源组件：FFmpeg / @ohos/ijkplayer（LGPL v2.1+，以动态共享库方式调用）、HarmonyOS NDK Media Kit、Remote Communication Kit、Universal Keystore Kit，均在设备本地运行，不单独收集个人信息。'
        ]
      },
      {
        title: '四、数据存储与保护',
        paragraphs: [
          '1. 所有片源账号与密码均通过系统硬件级密钥库（HUKS AES-256-GCM）加密后存储于设备本地，加密密钥由设备硬件保护，无法被导出。',
          '2. 本应用的所有网络代理均仅监听本机回环地址（127.0.0.1），不向局域网或外部开放任何端口。',
          '3. 卸载本应用即彻底删除全部本地数据，包括加密凭据、影库与播放历史。'
        ]
      },
      {
        title: '五、您的权利',
        paragraphs: [
          '1. 查询与更正：您可随时在应用内查看、修改您配置的片源信息与播放设置。',
          '2. 删除：您可随时在应用内删除片源、影库条目与播放历史；卸载应用即可删除全部本地数据。',
          '3. 撤回同意：您可以拒绝本政策（本应用将无法继续使用）；已同意后，您亦可卸载本应用以撤回全部授权。',
          '4. 如您认为我们处理个人信息的行为损害了您的合法权益，您可按本政策第八条方式与我们联系。'
        ]
      },
      {
        title: '六、未成年人保护',
        paragraphs: [
          '本应用为通用影音播放工具，不主动收集任何未成年人的个人信息。我们建议未成年人由监护人陪同使用，并由监护人自行决定所接入的媒体源内容。'
        ]
      },
      {
        title: '七、政策的更新',
        paragraphs: [
          '因法律法规变化或产品功能调整，我们可能适时更新本政策。更新后的政策将通过应用内展示的方式向您公布，重大变更将在您更新应用后再次提示。'
        ]
      },
      {
        title: '八、如何联系我们',
        paragraphs: [
          `如您对本政策或个人信息保护有任何疑问、意见或建议，可通过邮箱与我们联系：${AppConstants.SUPPORT_EMAIL}`,
          '我们将在收到您的反馈后十五个工作日内予以回复。'
        ]
      }
    ];
  }

  /** 《用户协议》：工具类付费应用的标准条款结构。 */
  private get agreementSections(): LegalSection[] {
    return [
      {
        title: '一、协议的接受与修改',
        paragraphs: [
          '本协议是您与开发者之间就使用棱镜影院 PrismPlayer（以下简称"本应用"）所订立的协议。您点击"同意并继续"或实际使用本应用，即视为您已阅读并同意本协议全部条款。',
          '我们可能根据法律法规变化或产品升级对本协议进行修订，修订后的协议将在应用内公布。若您不同意修订内容，可停止使用本应用。'
        ]
      },
      {
        title: '二、服务内容',
        paragraphs: [
          '1. 本应用是一款影音播放工具，仅提供对您自行合法获取并配置的本地文件、自有 NAS / WebDAV / SMB / Alist / Emby / Plex 等媒体源的解码播放与影库管理功能。',
          '2. 本应用不提供、不内置、不聚合任何第三方影视内容，不提供任何内容搜索、下载或转码分发服务。播放内容的获取与合法性由您自行负责。',
          '3. 基础播放功能免费使用；Pro 买断权益（无限片源数量、4K 硬解增强等）为可选付费项。'
        ]
      },
      {
        title: '三、付费与退款',
        paragraphs: [
          '1. Pro 权益采用华为应用内支付（IAP）一次性买断模式，无自动续费，不产生周期性扣费。',
          '2. 买断权益在同一华为账号下支持手机、平板、鸿蒙电脑多端通用。权益激活状态保存在本机，换机或重装后可通过同一华为账号恢复。',
          '3. 退款事宜按照华为应用市场（AppGallery）的支付与退款规则处理；如遇权益激活异常，可通过本协议第八条联系方式与我们沟通。'
        ]
      },
      {
        title: '四、用户行为规范',
        paragraphs: [
          '1. 您承诺使用本应用播放的内容均为您合法拥有或已获得授权的内容，不得利用本应用传播、展示任何侵犯他人著作权或其他合法权益的内容。',
          '2. 您不得对本应用进行反向工程、破解付费校验，或将本应用用于任何违反法律法规的用途。',
          '3. 因您违反前款规定产生的一切法律后果由您自行承担。'
        ]
      },
      {
        title: '五、知识产权与开源许可',
        paragraphs: [
          '本应用的界面、代码与商标归开发者所有。本应用使用了 FFmpeg / @ohos/ijkplayer 等开源组件（LGPL v2.1+，以动态共享库方式调用），相应组件的权利归属与许可条款以各开源项目原始声明为准。'
        ]
      },
      {
        title: '六、免责声明',
        paragraphs: [
          '1. 本应用按"现状"提供。对于因您配置的第三方媒体源不可用、网络故障、设备兼容性等非我们可控原因导致的功能异常，我们不承担责任。',
          '2. 对于您自行接入的媒体源内容之合法性、准确性，我们不作任何担保。'
        ]
      },
      {
        title: '七、服务的变更与终止',
        paragraphs: [
          '我们可能基于业务调整变更或中断部分服务。您可随时停止使用并卸载本应用；卸载即删除全部本地数据。'
        ]
      },
      {
        title: '八、法律适用与联系方式',
        paragraphs: [
          '本协议适用中华人民共和国法律。因本协议产生的争议，双方应友好协商解决；协商不成的，任何一方可向开发者所在地有管辖权的人民法院提起诉讼。',
          `对本协议有任何疑问，可通过邮箱与我们联系：${AppConstants.SUPPORT_EMAIL}`
        ]
      }
    ];
  }

  private get sections(): LegalSection[] {
    return this.docType === 'agreement' ? this.agreementSections : this.privacySections;
  }

  @Builder
  sectionCard(section: LegalSection) {
    Column({ space: 8 }) {
      Text(section.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      ForEach(section.paragraphs, (para: string) => {
        Text(para)
          .fontSize(13)
          .lineHeight(21)
          .fontColor($r('app.color.text_secondary'))
      }, (para: string, idx: number) => `${idx}_${para.substring(0, 12)}`)
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .backgroundColor($r('app.color.bg_elevated'))
    .border({ width: 0.8, color: $r('app.color.border_subtle') })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      NavHeaderBar({
        title: this.docTitle,
        subtitle: this.docSubtitle,
        onBack: () => this.getUIContext().getRouter().back()
      })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.sections, (section: LegalSection) => {
            this.sectionCard(section)
          }, (section: LegalSection) => section.title)

          Text(`棱镜影院 PrismPlayer · ${this.docTitle} · ${AppConstants.POLICY_UPDATED_DATE}`)
            .fontSize(11)
            .fontColor($r('app.color.text_muted'))
            .margin({ top: 4, bottom: 8 })
        }
        .padding({ left: 18, right: 18, top: 14, bottom: 32 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}

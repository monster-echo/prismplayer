
@ComponentV2
export struct PrivacyConsentDialog {
  @Param onAccept: () => void = () => {};
  @Param onDecline: () => void = () => {};
  @Param onOpenDoc: (docType: string) => void = (docType: string) => {};

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim_backdrop'))
        .backdropBlur(10)

      Column({ space: 16 }) {
        Row({ space: 10 }) {
          Column() {
            Text('P')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(36)
          .height(36)
          .borderRadius(10)
          .linearGradient({
            angle: 135,
            colors: [[$r('app.color.accent_blue'), 0], ['#7C5CFF', 1]]
          })
          .justifyContent(FlexAlign.Center)

          Column({ space: 2 }) {
            Text('欢迎使用棱镜播放器 PrismPlayer')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('纯血鸿蒙 + 鸿蒙电脑跨端影音播放器')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Column({ space: 10 }) {
          Text('隐私与权限说明')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text('1. 本应用定位为纯本地与用户自有私有云/WebDAV/NAS 协议播放器，绝不内置任何第三方影视源、爬虫或广告 SDK。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))

          Text('2. 您的 WebDAV/SMB 服务器地址与密码仅在设备本地通过系统 HUKS 硬件级加密存储，绝不会上传至开发者服务器。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))

          Text('3. 网络权限（ohos.permission.INTERNET）仅在您主动访问所配置的 WebDAV/Alist 媒体源或主动启用 TMDB 海报刮削时使用。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))

          // 审核要求：政策全文可点击查看，同意按钮须独立且默认不勾选
          Text() {
            Span('点击阅读并同意 ')
            Span('《用户协议》')
              .fontColor($r('app.color.accent_blue'))
              .onClick(() => this.onOpenDoc('agreement'))
            Span(' 与 ')
            Span('《隐私政策》')
              .fontColor($r('app.color.accent_blue'))
              .onClick(() => this.onOpenDoc('privacy'))
          }
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_secondary'))
        .border({ width: 1, color: $r('app.color.border_subtle') })
        .alignItems(HorizontalAlign.Start)

        Row({ space: 12 }) {
          Button('暂不使用')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.bg_elevated'))
            .borderRadius(10)
            .onClick(() => this.onDecline())

          Button('同意并继续')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.accent_blue'))
            .borderRadius(10)
            .onClick(() => this.onAccept())
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 460 })
      .padding(24)
      .borderRadius(18)
      .backgroundColor($r('app.color.bg_elevated'))
      .border({ width: 1, color: $r('app.color.border_subtle') })
    }
    .width('100%')
    .height('100%')
  }
}

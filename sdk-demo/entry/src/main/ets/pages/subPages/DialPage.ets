import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  DialDataType,
  DialInfoResult,
  CustomBgDialParams,
  UIStyleType,
  UIStyleResult,
} from '@veepoo/vpble-sdk';

@Entry
@Component
struct DialPage {
  @State isWriting: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  // 表盘信息读取结果
  @State dialResult: DialInfoResult | null = null;

  // 自定义背景参数
  @State bgDefault: boolean = false;
  @State bgTimePos: string = '1';
  @State bgTimeTop: string = '1';
  @State bgTimeBottom: string = '0';
  @State bgR: string = '255';
  @State bgG: string = '255';
  @State bgB: string = '255';

  // UI 风格
  @State uiStyle: string = '0';
  @State uiStyleType: UIStyleType = UIStyleType.FACTORY;
  @State uiResult: UIStyleResult | null = null;

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private clampInt(s: string, min: number, max: number, def: number): number {
    const n = parseInt(s, 10);
    if (isNaN(n)) {
      return def;
    }
    return Math.max(min, Math.min(max, n));
  }

  private hex2(n: number): string {
    return n.toString(16).padStart(2, '0');
  }

  private colorHex(): string {
    return `#${this.hex2(this.clampInt(this.bgR, 0, 255, 0))}`
      + `${this.hex2(this.clampInt(this.bgG, 0, 255, 0))}`
      + `${this.hex2(this.clampInt(this.bgB, 0, 255, 0))}`;
  }

  private dataTypeText(dt?: DialDataType): string {
    switch (dt) {
      case DialDataType.MARKET: return '市场表盘';
      case DialDataType.PHOTO: return '照片/背景表盘';
      case DialDataType.TOTAL_UI: return '全套 UI';
      default: return '--';
    }
  }

  private async readDial(dt: DialDataType): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const svc = VPBleSDK.getInstance().dialService;
      const r = dt === DialDataType.MARKET ? await svc.readMarketDial()
        : dt === DialDataType.PHOTO ? await svc.readPhotoDial()
          : await svc.readTotalDialInfo();
      this.dialResult = r;
      if (!r.success) {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async saveBg(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const params: CustomBgDialParams = {
        isDefaultBg: this.bgDefault ? 1 : 0,
        timePosition: this.clampInt(this.bgTimePos, 0, 7, 1),
        timeTopPosition: this.clampInt(this.bgTimeTop, 0, 7, 1),
        timeBottomPosition: this.clampInt(this.bgTimeBottom, 0, 7, 0),
        timeColor: [
          this.clampInt(this.bgR, 0, 255, 255),
          this.clampInt(this.bgG, 0, 255, 255),
          this.clampInt(this.bgB, 0, 255, 255),
        ],
      };
      const r = await VPBleSDK.getInstance().dialService.setCustomBackground(params);
      this.showToastMsg(r.success ? '自定义背景已保存' : `保存失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`保存异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async uiRead(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().dialService
        .readCustomUIStyle(this.clampInt(this.uiStyle, 0, 65535, 0), this.uiStyleType);
      this.uiResult = r;
      if (!r.success) {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async uiSet(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().dialService
        .setCustomUIStyle(this.clampInt(this.uiStyle, 0, 65535, 0), this.uiStyleType);
      this.uiResult = r;
      this.showToastMsg(r.success ? 'UI 风格已设置' : `设置失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`设置异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private showToastMsg(msg: string): void {
    this.toastMsg = msg;
    this.showToast = true;
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => { this.showToast = false; }, 2500);
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Text('<').fontSize(20).fontColor('#333333')
            .onClick(() => router.back()).padding({ right: 12 })
          Text('表盘与 UI').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.DialInfoCard()
            this.CustomBgCard()
            this.UIStyleCard()
          }.width('100%').padding({ bottom: 24 })
        }
        .width('100%').layoutWeight(1).align(Alignment.Top)
      }
      .width('100%').height('100%')

      if (this.showToast) {
        Text(this.toastMsg)
          .fontSize(14).fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .backgroundColor('rgba(0,0,0,0.7)').borderRadius(20).zIndex(1000)
      }
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  DialInfoCard() {
    Column({ space: 12 }) {
      Text('表盘信息读取（0x50）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')
      Row() {
        Button('市场表盘').fontSize(13).height(34).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.readDial(DialDataType.MARKET))
        Blank().width(8)
        Button('照片表盘').fontSize(13).height(34).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.readDial(DialDataType.PHOTO))
        Blank().width(8)
        Button('全套 UI').fontSize(13).height(34).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.readDial(DialDataType.TOTAL_UI))
      }.width('100%')

      if (this.dialResult) {
        Divider().color('#F0F0F0').margin({ top: 4, bottom: 4 })
        Text(`类型：${this.dataTypeText(this.dialResult.dataType)}`)
          .fontSize(13).fontColor('#999999').width('100%')
        if (this.dialResult.market) {
          this.MetricRow('写入地址', `0x${this.dialResult.market.dataAddress.toString(16).toUpperCase()}`)
          this.MetricRow('写入长度', `${this.dialResult.market.writeDataLength}`)
          this.MetricRow('bin 协议', `${this.dialResult.market.binProtocol}`)
          this.MetricRow('表盘形状', `${this.dialResult.market.dialShape}`)
          this.MetricRow('表盘 ID', `${this.dialResult.market.imageId}`)
        }
        if (this.dialResult.photo) {
          this.MetricRow('写入地址', `0x${this.dialResult.photo!.dataAddress.toString(16).toUpperCase()}`)
          this.MetricRow('写入长度', `${this.dialResult.photo!.writeDataLength}`)
          this.MetricRow('自定义类型', `${this.dialResult.photo!.customDialType}`)
          this.MetricRow('时间位置', `${this.dialResult.photo!.timePosition}（顶 ${this.dialResult.photo!.timeTopPosition} / 底 ${this.dialResult.photo!.timeBottomPosition}）`)
          this.MetricRow('元素颜色', `RGB(${this.dialResult.photo!.elementColor[0]}, ${this.dialResult.photo!.elementColor[1]}, ${this.dialResult.photo!.elementColor[2]})`)
          this.MetricRow('背景 CRC', `0x${this.dialResult.photo!.bgCrc.toString(16).toUpperCase()}`)
        }
        if (this.dialResult.total) {
          this.MetricRow('写入地址', `0x${this.dialResult.total.dataAddress.toString(16).toUpperCase()}`)
          this.MetricRow('写入长度', `${this.dialResult.total.writeDataLength}`)
        }
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  CustomBgCard() {
    Column({ space: 10 }) {
      Text('自定义背景（0x50,03,02）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      Row() {
        Text('设为默认表盘').fontSize(13).fontColor('#666666').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.bgDefault })
          .selectedColor('#007DFF')
          .onChange((on: boolean) => { this.bgDefault = on; })
      }.width('100%')

      Row() {
        Text('时间位置（0-7）').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.bgTimePos }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgTimePos = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('顶部时间位置（0-7）').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.bgTimeTop }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgTimeTop = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('底部时间位置（0-7）').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.bgTimeBottom }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgTimeBottom = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('时间颜色 RGB').fontSize(13).fontColor('#666666').layoutWeight(1)
        Row().width(24).height(24).backgroundColor(this.colorHex()).borderRadius(4)
          .border({ width: 1, color: '#E0E0E0' })
      }.width('100%')
      Row() {
        Text('R').fontSize(13).fontColor('#666666').width(20)
        TextInput({ text: this.bgR }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgR = v; })
        Blank().width(8)
        Text('G').fontSize(13).fontColor('#666666').width(20)
        TextInput({ text: this.bgG }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgG = v; })
        Blank().width(8)
        Text('B').fontSize(13).fontColor('#666666').width(20)
        TextInput({ text: this.bgB }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgB = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Button('保存').width('100%').height(40)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(8)
        .enabled(!this.isWriting)
        .onClick(() => this.saveBg())
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  UIStyleCard() {
    Column({ space: 10 }) {
      Text('UI 风格（0xC7）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      Row() {
        Text('style').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.uiStyle }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.uiStyle = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('styleType').fontSize(13).fontColor('#666666').width(72)
        this.StyleTypeTab(UIStyleType.FACTORY, '出厂')
        this.StyleTypeTab(UIStyleType.CUSTOM, '自定义')
        this.StyleTypeTab(UIStyleType.OTHER, '其他')
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Button('读取').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#34C759').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.uiRead())
        Blank().width(8)
        Button('设置').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#FF9500').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.uiSet())
      }.width('100%')

      if (this.uiResult) {
        Divider().color('#F0F0F0').margin({ top: 4, bottom: 4 })
        this.MetricRow('ack', this.uiResult.ack !== undefined ? `${this.uiResult.ack}` : '--')
        this.MetricRow('style', this.uiResult.style !== undefined ? `${this.uiResult.style}` : '--')
        this.MetricRow('styleType', this.uiResult.styleType !== undefined ? `${this.uiResult.styleType}` : '--')
        if (this.uiResult.data && this.uiResult.data.length > 0) {
          this.MetricRow('数据', this.uiResult.data.join(', '))
        }
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  @Builder
  StyleTypeTab(t: UIStyleType, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.uiStyleType === t ? Color.White : '#666666')
      .backgroundColor(this.uiStyleType === t ? '#007DFF' : '#F0F0F0')
      .borderRadius(6)
      .height(28)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .margin({ left: 6 })
      .onClick(() => { this.uiStyleType = t; })
  }

  @Builder
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#333333').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '62%' })
    }.width('100%').height(40)
  }
}

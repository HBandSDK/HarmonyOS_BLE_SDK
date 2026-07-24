import { router } from '@kit.ArkUI';
import { VPBleSDK, ManualMeasurementType, ManualMeasurementPushEvent } from '@veepoo/vpble-sdk';

interface ManualRouteParams {
  type: number;
  title: string;
}

function toHexPreview(bytes: number[]): string {
  const limit = bytes.length > 64 ? 64 : bytes.length;
  const parts: string[] = [];
  for (let i = 0; i < limit; i++) {
    parts.push(bytes[i].toString(16).padStart(2, '0'));
  }
  let s = parts.join(' ');
  if (bytes.length > 64) {
    s += ' ...';
  }
  return s;
}

@Entry
@Component
struct ManualMeasurePage {
  @State title: string = '微体检';
  @State querying: boolean = false;
  @State progress: number = 0;
  @State byteLen: number = 0;
  @State hexPreview: string = '';
  @State logMsg: string = '';
  private _manualType: number = 9;

  private _listener: ((event: ManualMeasurementPushEvent) => void) | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as ManualRouteParams;
    if (params) {
      this._manualType = params.type;
      this.title = params.title;
    }

    this._listener = (event: ManualMeasurementPushEvent) => {
      this.progress = event.progress;
      if (event.isComplete && event.mergedPayload) {
        this.byteLen = event.mergedPayload.length;
        this.hexPreview = toHexPreview(event.mergedPayload);
        this.querying = false;
        this.logMsg = `完成：收到 ${event.mergedPayload.length} 字节`;
      } else {
        this.logMsg = `进度 ${event.progress}%`;
      }
    };
    VPBleSDK.getInstance().manualMeasurementService.onManualMeasurementPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().manualMeasurementService.offManualMeasurementPush(this._listener);
      this._listener = null;
    }
  }

  private async query(): Promise<void> {
    if (this.querying) {
      return;
    }
    this.querying = true;
    this.progress = 0;
    this.byteLen = 0;
    this.hexPreview = '';
    const types: ManualMeasurementType[] = [this._manualType as ManualMeasurementType];
    const r = await VPBleSDK.getInstance().manualMeasurementService.startMeasurement(types);
    if (r.success) {
      this.logMsg = '已发起查询，等待推送...';
    } else {
      this.querying = false;
      this.logMsg = `发起失败：${r.errorMessage ?? '未知'}`;
    }
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text(this.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Text('走 0xDE 手动测量协议，设备多包回传合并后的原始字节需按业务自行解码')
        .fontSize(12).fontColor('#999999')
        .margin({ left: 16, right: 16, top: 12 })

      Column({ space: 10 }) {
        Row() {
          Text('进度').fontSize(14).fontColor('#666666').layoutWeight(1)
          Text(`${this.progress}%`).fontSize(14).fontColor('#333333')
        }.width('100%')
        Row() {
          Text('数据长度').fontSize(14).fontColor('#666666').layoutWeight(1)
          Text(this.byteLen > 0 ? `${this.byteLen} 字节` : '--').fontSize(14).fontColor('#333333')
        }.width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ left: 16, right: 16, top: 12 })

      if (this.hexPreview) {
        Text(this.hexPreview)
          .fontSize(11).fontColor('#666666').fontFamily('monospace')
          .width('100%').padding(12)
          .backgroundColor(Color.White).borderRadius(8)
          .margin({ left: 16, right: 16, top: 12 })
      }

      Blank().layoutWeight(1)

      Button(this.querying ? '查询中' : '发起查询')
        .width('60%').height(44).margin({ bottom: 16 })
        .backgroundColor(this.querying ? '#CCCCCC' : '#007DFF')
        .fontColor(Color.White).borderRadius(8)
        .enabled(!this.querying)
        .onClick(() => this.query())

      if (this.logMsg) {
        Text(this.logMsg).fontSize(13).fontColor('#666666')
          .margin({ left: 24, right: 24, bottom: 16 }).textAlign(TextAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}

import { router } from '@kit.ArkUI';
import { VPBleSDK, HeartRateMeasurement, HeartRateBrightness } from '@veepoo/vpble-sdk';

@Entry
@Component
struct HrPage {
  @State measuring: boolean = false;
  @State heartRate: number = 0;
  @State heartState: number = 0;
  @State watchState: number = 0;
  @State logMsg: string = '';

  private _listener: ((data: HeartRateMeasurement) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (data: HeartRateMeasurement) => {
      this.heartRate = data.heartRate;
      this.heartState = data.heartState;
      this.watchState = data.watchState;
      this.logMsg = `推送：${data.heartRate} BPM（state=${data.heartState}, watch=${data.watchState}）`;
    };
    VPBleSDK.getInstance().heartRateService.onHeartRatePush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().heartRateService.offHeartRatePush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().heartRateService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().heartRateService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.heartRate = 0;
      const r = await VPBleSDK.getInstance().heartRateService.startMeasurement(HeartRateBrightness.HIGH);
      if (r.success) {
        this.measuring = true;
        this.logMsg = '开始测量，等待推送...';
      } else {
        this.logMsg = `启动失败：${r.errorMessage ?? '未知'}`;
      }
    }
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('心率测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        Text(this.heartRate > 0 ? `${this.heartRate}` : '--')
          .fontSize(64).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
        Text('BPM').fontSize(14).fontColor('#999999')
      }.width('100%').padding({ top: 36, bottom: 24 })

      Button(this.measuring ? '停止测量' : '开始测量')
        .width('60%').height(44)
        .backgroundColor(this.measuring ? '#E84026' : '#007DFF')
        .fontColor(Color.White).borderRadius(8)
        .onClick(() => this.toggle())

      if (this.logMsg) {
        Text(this.logMsg).fontSize(13).fontColor('#666666')
          .margin({ top: 24, left: 24, right: 24 }).textAlign(TextAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}

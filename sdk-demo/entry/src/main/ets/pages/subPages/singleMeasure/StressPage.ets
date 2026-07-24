import { router } from '@kit.ArkUI';
import { VPBleSDK, StressMeasurement } from '@veepoo/vpble-sdk';

@Entry
@Component
struct StressPage {
  @State measuring: boolean = false;
  @State pressure: number = 0;
  @State progress: number = 0;
  @State logMsg: string = '';

  private _listener: ((data: StressMeasurement) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (data: StressMeasurement) => {
      this.pressure = data.pressure;
      this.progress = data.progress;
      this.logMsg = `推送：压力 ${data.pressure} (${data.progress}%)`;
    };
    VPBleSDK.getInstance().stressService.onStressPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().stressService.offStressPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().stressService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().stressService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.pressure = 0;
      this.progress = 0;
      const r = await VPBleSDK.getInstance().stressService.startMeasurement();
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
        Text('压力测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        Text(this.pressure > 0 ? `${this.pressure}` : '--')
          .fontSize(64).fontWeight(FontWeight.Bold).fontColor('#5856D6')
        Text('压力值').fontSize(14).fontColor('#999999')
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(16).fontColor('#FF9800').margin({ top: 12 })
        }
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

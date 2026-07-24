import { router } from '@kit.ArkUI';
import { VPBleSDK, BloodPressureResult } from '@veepoo/vpble-sdk';

@Entry
@Component
struct BpPage {
  @State measuring: boolean = false;
  @State systolic: number = 0;
  @State diastolic: number = 0;
  @State progress: number = 0;
  @State logMsg: string = '';

  private _listener: ((data: BloodPressureResult) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (data: BloodPressureResult) => {
      const m = data.data;
      if (m) {
        this.systolic = m.systolic;
        this.diastolic = m.diastolic;
        this.progress = m.progress;
        this.logMsg = `推送：${m.systolic}/${m.diastolic} mmHg (${m.progress}%)`;
      }
    };
    VPBleSDK.getInstance().bloodPressureService.onBloodPressurePush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().bloodPressureService.offBloodPressurePush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().bloodPressureService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().bloodPressureService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.systolic = 0;
      this.diastolic = 0;
      this.progress = 0;
      const r = await VPBleSDK.getInstance().bloodPressureService.startMeasurement(false);
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
        Text('血压测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        Row() {
          Text(this.systolic > 0 ? `${this.systolic}` : '--')
            .fontSize(56).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
          Text('/').fontSize(40).fontColor('#999999').margin({ left: 8, right: 8 })
          Text(this.diastolic > 0 ? `${this.diastolic}` : '--')
            .fontSize(56).fontWeight(FontWeight.Bold).fontColor('#007DFF')
        }
        Text('mmHg').fontSize(14).fontColor('#999999')
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(16).fontColor('#FF9800')
            .margin({ top: 16 })
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

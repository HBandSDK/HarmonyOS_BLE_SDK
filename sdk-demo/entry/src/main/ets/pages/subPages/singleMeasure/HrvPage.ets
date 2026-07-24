import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  EcgPushEvent,
  EcgPushEventKind,
  EcgSecondMeasurement,
  EcgDiagnosis,
} from '@veepoo/vpble-sdk';

@Entry
@Component
struct HrvPage {
  @State measuring: boolean = false;
  @State progress: number = 0;
  @State hrv: number = 0;
  @State sdnn: number = 0;
  @State rmssd: number = 0;
  @State logMsg: string = '';

  private _listener: ((event: EcgPushEvent) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (event: EcgPushEvent) => {
      if (event.kind === EcgPushEventKind.PROGRESS) {
        const d = event.data as EcgSecondMeasurement;
        this.progress = d.progress;
        this.hrv = d.hrv;
        this.logMsg = `进度 ${d.progress}% HRV=${d.hrv}`;
      } else if (event.kind === EcgPushEventKind.RESULT) {
        const d = event.data as EcgDiagnosis;
        this.hrv = d.hrv;
        this.sdnn = d.sdnn;
        this.rmssd = d.rmssd;
        this.progress = 100;
        this.logMsg = `诊断完成：HRV=${d.hrv} SDNN=${d.sdnn}ms RMSSD=${d.rmssd}ms`;
      }
    };
    VPBleSDK.getInstance().ecgService.onEcgPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().ecgService.offEcgPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().ecgService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().ecgService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.progress = 0;
      this.hrv = 0;
      this.sdnn = 0;
      this.rmssd = 0;
      const r = await VPBleSDK.getInstance().ecgService.startMeasurement();
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
        Text('HRV 测量（经 ECG）').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Row() {
        Column() {
          Text(this.hrv > 0 ? `${this.hrv}` : '--').fontSize(32).fontWeight(FontWeight.Bold).fontColor('#5856D6')
          Text('HRV').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(this.sdnn > 0 ? `${this.sdnn}` : '--').fontSize(32).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
          Text('SDNN(ms)').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(this.rmssd > 0 ? `${this.rmssd}` : '--').fontSize(32).fontWeight(FontWeight.Bold).fontColor('#34C759')
          Text('RMSSD(ms)').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
      }.width('100%').padding({ top: 28, bottom: 16 })

      if (this.measuring) {
        Text(`${this.progress}%`).fontSize(16).fontColor('#FF9800').margin({ bottom: 16 })
      }

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

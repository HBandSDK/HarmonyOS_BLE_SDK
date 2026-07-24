import { router } from '@kit.ArkUI';
import { VPBleSDK, BloodSugarResult, BloodSugarRiskLevel } from '@veepoo/vpble-sdk';

const RISK_LABELS: string[] = ['无', '偏低', '正常', '偏高'];

@Entry
@Component
struct BloodSugarPage {
  @State measuring: boolean = false;
  @State bloodSugar: number = 0;
  @State progress: number = 0;
  @State riskLevel: number = 0;
  @State logMsg: string = '';

  private _listener: ((data: BloodSugarResult) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (data: BloodSugarResult) => {
      const m = data.data;
      if (m) {
        this.bloodSugar = m.bloodSugar;
        this.progress = m.progress;
        this.riskLevel = m.riskLevel;
        this.logMsg = `推送：${m.bloodSugar} mmol/L (${m.progress}%) 风险=${RISK_LABELS[m.riskLevel] ?? m.riskLevel}`;
      }
    };
    VPBleSDK.getInstance().bloodSugarService.onBloodSugarPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().bloodSugarService.offBloodSugarPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().bloodSugarService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().bloodSugarService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.bloodSugar = 0;
      this.progress = 0;
      this.riskLevel = BloodSugarRiskLevel.NONE;
      const r = await VPBleSDK.getInstance().bloodSugarService.startMeasurement(false);
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
        Text('血糖测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        Text(this.bloodSugar > 0 ? `${this.bloodSugar}` : '--')
          .fontSize(64).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
        Text('mmol/L').fontSize(14).fontColor('#999999')
        if (this.riskLevel > 0) {
          Text(`风险：${RISK_LABELS[this.riskLevel] ?? this.riskLevel}`)
            .fontSize(14).fontColor('#FF9800').margin({ top: 8 })
        }
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(16).fontColor('#FF9800').margin({ top: 12 })
        }
      }.width('100%').padding({ top: 28, bottom: 24 })

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

import { router } from '@kit.ArkUI';
import { VPBleSDK, BloodComponentsResult, BloodComponentsMeasurement } from '@veepoo/vpble-sdk';

@Entry
@Component
struct BloodComponentsPage {
  @State measuring: boolean = false;
  @State progress: number = 0;
  @State result: BloodComponentsMeasurement | null = null;
  @State logMsg: string = '';

  private _listener: ((data: BloodComponentsResult) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (data: BloodComponentsResult) => {
      const m = data.data;
      if (m) {
        this.result = m;
        this.progress = m.progress;
        this.logMsg = `推送：尿酸 ${m.uricAcid} / 总胆固醇 ${m.cholesterol} (${m.progress}%)`;
      }
    };
    VPBleSDK.getInstance().bloodComponentsService.onBloodComponentsPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().bloodComponentsService.offBloodComponentsPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().bloodComponentsService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().bloodComponentsService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.result = null;
      this.progress = 0;
      const r = await VPBleSDK.getInstance().bloodComponentsService.startMeasurement(false);
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
        Text('血液成分测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(13).fontColor('#FF9800').margin({ left: 8 })
        }
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column() {
        this.MetricRow('尿酸', this.result?.uricAcid ?? 0, 'μmol/L')
        this.MetricRow('总胆固醇', this.result?.cholesterol ?? 0, 'mmol/L')
        this.MetricRow('甘油三酯', this.result?.triglyceride ?? 0, 'mmol/L')
        this.MetricRow('高密度脂蛋白', this.result?.highDensity ?? 0, 'mmol/L')
        this.MetricRow('低密度脂蛋白', this.result?.lowDensity ?? 0, 'mmol/L')
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ left: 16, right: 16, top: 16 })

      Button(this.measuring ? '停止测量' : '开始测量')
        .width('60%').height(44).margin({ top: 16, bottom: 16 })
        .backgroundColor(this.measuring ? '#E84026' : '#007DFF')
        .fontColor(Color.White).borderRadius(8)
        .onClick(() => this.toggle())

      if (this.logMsg) {
        Text(this.logMsg).fontSize(13).fontColor('#666666')
          .margin({ left: 24, right: 24, bottom: 16 }).textAlign(TextAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  MetricRow(label: string, value: number, unit: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#666666').layoutWeight(1)
      Text(value > 0 ? `${value} ${unit}` : '--').fontSize(14).fontColor('#333333')
    }.width('100%').height(48).padding({ left: 16, right: 16 })
  }
}

import { router } from '@kit.ArkUI';
import { VPBleSDK, SkinElectricData } from '@veepoo/vpble-sdk';

@Entry
@Component
struct SkinElectricPage {
  @State measuring: boolean = false;
  @State progress: number = 0;
  @State result: SkinElectricData | null = null;
  @State logMsg: string = '';

  private _listener: ((data: SkinElectricData) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (data: SkinElectricData) => {
      this.result = data;
      this.progress = data.progress;
      this.logMsg = `推送：情绪 ${data.emotionLevel} 湿度 ${data.skinMoisture} (${data.progress}%)`;
    };
    VPBleSDK.getInstance().skinElectricService.onSkinElectricPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().skinElectricService.offSkinElectricPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().skinElectricService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().skinElectricService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.result = null;
      this.progress = 0;
      const r = await VPBleSDK.getInstance().skinElectricService.startMeasurement();
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
        Text('皮肤电测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(13).fontColor('#FF9800').margin({ left: 8 })
        }
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column() {
        this.MetricRow('测量进度', this.result?.progress ?? 0, '%')
        this.MetricRow('情绪等级', this.result?.emotionLevel ?? 0, '')
        this.MetricRow('皮肤湿度', this.result?.skinMoisture ?? 0, '')
        this.MetricRow('抑郁风险', this.result?.depressionRisk ?? 0, '')
        this.MetricRow('交感神经激活度', this.result?.snsActivation ?? 0, '')
        this.MetricRow('皮质醇值', this.result?.cortisolValue ?? 0, '')
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
      Text(unit ? `${value} ${unit}` : `${value}`).fontSize(14).fontColor('#333333')
    }.width('100%').height(48).padding({ left: 16, right: 16 })
  }
}

import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  BodyCompPushEvent,
  BodyCompPushEventKind,
  BodyCompProgress,
  BodyCompositionMeasurement,
} from '@veepoo/vpble-sdk';

@Entry
@Component
struct BodyCompPage {
  @State measuring: boolean = false;
  @State progress: number = 0;
  @State result: BodyCompositionMeasurement | null = null;
  @State logMsg: string = '';

  private _listener: ((event: BodyCompPushEvent) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (event: BodyCompPushEvent) => {
      if (event.kind === BodyCompPushEventKind.PROGRESS) {
        const p = event.data as BodyCompProgress;
        this.progress = p.progress;
        this.logMsg = `进度 ${p.progress}%`;
      } else if (event.kind === BodyCompPushEventKind.RESULT) {
        const m = event.data as BodyCompositionMeasurement;
        this.result = m;
        this.progress = 100;
        this.logMsg = `结果：BMI ${m.bmi} 体脂率 ${m.bodyFatPercentage}%`;
      }
    };
    VPBleSDK.getInstance().bodyCompositionService.onBodyCompPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().bodyCompositionService.offBodyCompPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().bodyCompositionService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().bodyCompositionService.stopMeasurement();
      this.measuring = false;
      this.logMsg = `已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`;
    } else {
      this.result = null;
      this.progress = 0;
      const r = await VPBleSDK.getInstance().bodyCompositionService.startMeasurement();
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
        Text('身体成分测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(13).fontColor('#FF9800').margin({ left: 8 })
        }
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          this.MetricRow('BMI', this.result?.bmi ?? 0, '')
          this.MetricRow('体脂率', this.result?.bodyFatPercentage ?? 0, '%')
          this.MetricRow('脂肪量', this.result?.fatMass ?? 0, '')
          this.MetricRow('去脂体重', this.result?.leanBodyMass ?? 0, '')
          this.MetricRow('肌肉率', this.result?.muscleRate ?? 0, '%')
          this.MetricRow('肌肉量', this.result?.muscleMass ?? 0, '')
          this.MetricRow('皮下脂肪', this.result?.subcutaneousFat ?? 0, '')
          this.MetricRow('体内水分', this.result?.bodyMoisture ?? 0, '')
          this.MetricRow('含水量', this.result?.waterContent ?? 0, '%')
          this.MetricRow('骨骼肌率', this.result?.skeletalMuscleRate ?? 0, '%')
          this.MetricRow('骨量', this.result?.boneMass ?? 0, '')
          this.MetricRow('蛋白质占比', this.result?.proteinPercentage ?? 0, '%')
          this.MetricRow('蛋白质量', this.result?.proteinAmount ?? 0, '')
          this.MetricRow('基础代谢率', this.result?.basalMetabolicRate ?? 0, '')
        }.width('100%')
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
    }.width('100%').height(44).padding({ left: 16, right: 16 })
  }
}

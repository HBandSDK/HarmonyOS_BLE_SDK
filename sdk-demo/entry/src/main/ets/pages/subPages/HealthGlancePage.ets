import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  HealthGlanceState,
  HealthGlanceType,
  HealthGlanceTestModel,
  HealthGlanceProgressListener,
  HealthGlanceCompleteListener,
  HealthGlanceErrorListener,
} from '@veepoo/vpble-sdk';

/**
 * 微体检（HealthGlance）示例
 *
 * 一次测量同时采集心率/血氧/血压/血糖/体温/身体成分/血液成分/皮电等多项，
 * 具体采集哪些由设备决定，结果模型的 functionSupport 位掩码给出实际覆盖项。
 *
 * 用法要点：
 *   1. onHealthGlanceProgress / Complete / Error 三个监听在 aboutToAppear 注册、
 *      aboutToDisappear 注销（务必成对，否则页面销毁后回调泄漏）；
 *   2. startMeasurement() 是「发后不等」——它的 Promise 只代表命令已下发，
 *      真正的进度与结果都走监听回调；
 *   3. stopMeasurement() 的设备回包状态码不在映射表内，SDK 一律归为
 *      HealthGlanceState.NoFunction，属正常回包，这里静默忽略。
 */
@Entry
@Component
struct HealthGlancePage {
  @State measuring: boolean = false;
  @State progress: number = 0;
  @State model: HealthGlanceTestModel | null = null;
  @State logMsg: string = '';

  private _onProgress: HealthGlanceProgressListener | null = null;
  private _onComplete: HealthGlanceCompleteListener | null = null;
  private _onError: HealthGlanceErrorListener | null = null;

  aboutToAppear(): void {
    const svc = VPBleSDK.getInstance().healthGlanceService;

    this._onProgress = (progress: number) => {
      this.progress = progress;
      this.logMsg = `测量中 ${progress}%`;
    };
    this._onComplete = (model: HealthGlanceTestModel) => {
      this.measuring = false;
      this.progress = 100;
      this.model = model;
      this.logMsg = `测量完成，覆盖项掩码 0x${model.functionSupport.toString(16)}`;
    };
    this._onError = (state: HealthGlanceState, errorMessage?: string) => {
      // 停止命令的正常回包会落到 NoFunction，不是真错误
      if (state === HealthGlanceState.NoFunction) {
        return;
      }
      this.measuring = false;
      this.progress = 0;
      this.logMsg = `测量失败：${this.stateText(state)}${errorMessage ? ' - ' + errorMessage : ''}`;
    };

    svc.onHealthGlanceProgress(this._onProgress!);
    svc.onHealthGlanceComplete(this._onComplete!);
    svc.onHealthGlanceError(this._onError!);

    this.logMsg = svc.isSupported() ? '设备支持微体检，可开始测量' : '当前设备不支持微体检';
  }

  aboutToDisappear(): void {
    const svc = VPBleSDK.getInstance().healthGlanceService;
    if (this._onProgress) {
      svc.offHealthGlanceProgress(this._onProgress);
      this._onProgress = null;
    }
    if (this._onComplete) {
      svc.offHealthGlanceComplete(this._onComplete);
      this._onComplete = null;
    }
    if (this._onError) {
      svc.offHealthGlanceError(this._onError);
      this._onError = null;
    }
    if (this.measuring) {
      svc.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    const svc = VPBleSDK.getInstance().healthGlanceService;
    if (this.measuring) {
      await svc.stopMeasurement();
      this.measuring = false;
      this.logMsg = '已停止';
      return;
    }
    if (!svc.isSupported()) {
      this.logMsg = '当前设备不支持微体检';
      return;
    }
    this.model = null;
    this.progress = 0;
    const r = await svc.startMeasurement();
    if (r.success) {
      this.measuring = true;
      this.logMsg = '已下发开始命令，等待进度推送...';
    } else {
      this.logMsg = `启动失败：${r.errorMessage ?? '未知'}`;
    }
  }

  private stateText(state: HealthGlanceState): string {
    switch (state) {
      case HealthGlanceState.DeviceBusy: return '设备忙';
      case HealthGlanceState.LowPower: return '电量低';
      case HealthGlanceState.NotWear: return '未佩戴';
      case HealthGlanceState.NotLead: return '未接触导联';
      case HealthGlanceState.Complete: return '已完成';
      default: return '功能不支持/未知';
    }
  }

  /** functionSupport 位掩码 → 可读的覆盖项列表 */
  private supportText(mask: number): string {
    const names: string[] = [];
    if (mask & HealthGlanceType.HeartValue) names.push('心率');
    if (mask & HealthGlanceType.BloodOxy) names.push('血氧');
    if (mask & HealthGlanceType.PpgBp) names.push('光电血压');
    if (mask & HealthGlanceType.CuffBp) names.push('气泵血压');
    if (mask & HealthGlanceType.BloodGlucose) names.push('血糖');
    if (mask & HealthGlanceType.BodyTemp) names.push('体温');
    if (mask & HealthGlanceType.BodyComp) names.push('身体成分');
    if (mask & HealthGlanceType.BloodComp) names.push('血液成分');
    if (mask & HealthGlanceType.GSR) names.push('皮电');
    if (mask & HealthGlanceType.Stress) names.push('压力');
    if (mask & HealthGlanceType.Emotion) names.push('情绪');
    if (mask & HealthGlanceType.Fatigue) names.push('疲劳');
    if (mask & HealthGlanceType.HRV) names.push('HRV');
    return names.length > 0 ? names.join('、') : '--';
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('微体检').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
        if (this.measuring) {
          Text(`${this.progress}%`).fontSize(13).fontColor('#FF9800').margin({ left: 8 })
        }
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          this.MetricRow('覆盖项', this.model ? this.supportText(this.model.functionSupport) : '--')
          this.MetricRow('心率', this.model ? `${this.model.heartRate} bpm` : '--')
          this.MetricRow('血氧', this.model ? `${this.model.bloodOxygen} %` : '--')
          this.MetricRow('光电血压', this.model ? `${this.model.ppgBloodPressureHigh}/${this.model.ppgBloodPressureLow} mmHg` : '--')
          this.MetricRow('气泵血压', this.model ? `${this.model.cuffBloodPressureHigh}/${this.model.cuffBloodPressureLow} mmHg` : '--')
          this.MetricRow('血糖', this.model ? (this.model.bloodSugarType === 1 ? `${this.model.bloodSugar}` : `等级 ${this.model.bloodSugarLevel}`) : '--')
          this.MetricRow('体温', this.model ? `${this.model.bodyTemperature} °C` : '--')
          this.MetricRow('压力', this.model ? `${this.model.stress}` : '--')
          this.MetricRow('HRV', this.model ? `${this.model.hrv}` : '--')
          this.MetricRow('疲劳度', this.model ? `${this.model.fatigueLevel}` : '--')
          this.MetricRow('情绪', this.model ? `${this.model.emotionLevel}` : '--')
          this.MetricRow('BMI', this.model ? `${this.model.bmi}` : '--')
          this.MetricRow('体脂率', this.model ? `${this.model.bodyFatPercentage} %` : '--')
          this.MetricRow('基础代谢', this.model ? `${this.model.basalMetabolicRate} kcal` : '--')
          this.MetricRow('尿酸', this.model ? `${this.model.uricAcid}` : '--')
          this.MetricRow('总胆固醇', this.model ? `${this.model.totalCholesterol}` : '--')
          this.MetricRow('皮肤含水量', this.model ? `${this.model.skinMoisture}` : '--')
          this.MetricRow('皮质醇', this.model ? `${this.model.cortisolValue} ug/L` : '--')
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
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(14).fontColor('#333333')
    }.width('100%').height(44).padding({ left: 16, right: 16 })
  }
}

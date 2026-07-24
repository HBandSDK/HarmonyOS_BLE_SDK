import { router } from '@kit.ArkUI';
import { VPBleSDK, HealthQueryDay, HealthData, DailyFiveData } from '@veepoo/vpble-sdk';

@Entry
@Component
struct DailyDataPage {
  @State hasQueried: boolean = false;
  @State selectedDay: HealthQueryDay = HealthQueryDay.TODAY;
  @State querying: boolean = false;
  @State progressPct: number = 0;
  @State progressText: string = '';
  @State hasData: boolean = false;
  @State hasError: boolean = false;
  @State logMsg: string = '';

  // 运动汇总（直接取自 sportSummary）
  @State totalSteps: number = 0;
  @State totalDistance: number = 0; // km
  @State totalCalories: number = 0; // kcal
  @State slotCount: number = 0;
  @State timeStart: string = '';
  @State timeEnd: string = '';

  // 按小时步数（24）
  @State hourlySteps: number[] = [];
  @State maxHourlySteps: number = 0;
  @State peakHour: number = -1;

  // 心率（由 ecgs 聚合）
  @State hrAvg: number = 0;
  @State hrMax: number = 0;
  @State hrMin: number = 0;

  // 健康指标
  @State spo2Avg: number = 0;
  @State bpSys: number = 0;
  @State bpDia: number = 0;
  @State bodyTemp: number = 0; // °C
  @State bloodGlucose: number = 0; // mmol/L
  @State bloodGlucoseLevel: number = 0;
  @State stressAvg: number = 0;

  private queryHealthData(day: HealthQueryDay): void {
    if (this.querying) {
      return;
    }
    this.querying = true;
    this.hasQueried = true;
    this.selectedDay = day;
    this.hasError = false;
    this.logMsg = '';
    this.hasData = false;
    this.progressPct = 0;
    this.progressText = '';
    VPBleSDK.getInstance().healthService.getHealthData(day, 1, (progress: number) => {
      this.progressPct = Math.min(100, Math.round(progress * 100));
      this.progressText = `${this.progressPct}%`;
    }).then((result) => {
      const data = result.data;
      if (result.success && data && data.fiveMinuteData.length > 0) {
        this.computeAggregates(data);
      } else if (result.success) {
        this.logMsg = '当天无日常健康数据';
      } else {
        this.hasError = true;
        this.logMsg = `查询失败: ${result.errorMessage ?? '未知错误'}`;
      }
    }).catch((err: Error) => {
      this.hasError = true;
      this.logMsg = `错误: ${err.message}`;
    }).finally(() => {
      this.querying = false;
      this.progressText = '';
      this.progressPct = 0;
    });
  }

  // 由 5 分钟分片聚合成日级展示数据
  private computeAggregates(data: HealthData): void {
    this.totalSteps = data.sportSummary.totalSteps;
    this.totalDistance = data.sportSummary.totalDistance;
    this.totalCalories = data.sportSummary.totalCalories;

    // 按时间升序，便于取“最新”值与时间范围
    const slots: DailyFiveData[] = data.fiveMinuteData.slice()
      .sort((a: DailyFiveData, b: DailyFiveData) => a.time - b.time);
    this.slotCount = slots.length;

    const validTimes: number[] = slots
      .filter((s: DailyFiveData) => s.time !== 0xFFFF && s.time <= 1435)
      .map((s: DailyFiveData) => s.time);
    this.timeStart = validTimes.length > 0 ? this.minToHHmm(validTimes[0]) : '--:--';
    this.timeEnd = validTimes.length > 0 ? this.minToHHmm(validTimes[validTimes.length - 1]) : '--:--';

    // 按小时累加步数
    const hourly: number[] = new Array<number>(24).fill(0);
    for (const s of slots) {
      if (s.time === 0xFFFF || s.time > 1435) {
        continue;
      }
      const h = Math.floor(s.time / 60);
      if (h >= 0 && h < 24) {
        hourly[h] += s.steps;
      }
    }
    this.hourlySteps = hourly;
    let maxH = 0;
    let peak = -1;
    for (let h = 0; h < 24; h++) {
      if (hourly[h] > maxH) {
        maxH = hourly[h];
        peak = h;
      }
    }
    this.maxHourlySteps = maxH;
    this.peakHour = peak;

    // 心率 / 血氧 / 压力 聚合，最新值取排序后最后一个有效分片
    let hrSum = 0, hrCnt = 0, hrMax = 0, hrMin = 999;
    let spo2Sum = 0, spo2Cnt = 0;
    let stressSum = 0, stressCnt = 0;
    let bpS = 0, bpD = 0;
    let temp = 0;
    let glucose = 0, glucoseLevel = 0;
    for (const s of slots) {
      for (const v of s.ecgs) {
        if (v > 0) {
          hrSum += v;
          hrCnt++;
          if (v > hrMax) hrMax = v;
          if (v < hrMin) hrMin = v;
        }
      }
      for (const v of s.spO2Values) {
        if (v > 0 && v <= 100) {
          spo2Sum += v;
          spo2Cnt++;
        }
      }
      if (s.stress > 0) {
        stressSum += s.stress;
        stressCnt++;
      }
      if (s.systolicBP > 0 && s.diastolicBP > 0) {
        bpS = s.systolicBP;
        bpD = s.diastolicBP;
      }
      if (s.bodyTemp > 0) {
        temp = s.bodyTemp;
      }
      if (s.bloodGlucose > 0) {
        glucose = s.bloodGlucose;
        glucoseLevel = s.bloodGlucoseLevel;
      }
    }
    this.hrAvg = hrCnt > 0 ? Math.round(hrSum / hrCnt) : 0;
    this.hrMax = hrMax;
    this.hrMin = hrMin === 999 ? 0 : hrMin;
    this.spo2Avg = spo2Cnt > 0 ? Math.round(spo2Sum / spo2Cnt) : 0;
    this.stressAvg = stressCnt > 0 ? Math.round(stressSum / stressCnt) : 0;
    this.bpSys = bpS;
    this.bpDia = bpD;
    this.bodyTemp = temp;
    this.bloodGlucose = glucose;
    this.bloodGlucoseLevel = glucoseLevel;

    this.hasData = true;
  }

  private minToHHmm(min: number): string {
    const h = Math.floor(min / 60);
    const m = min % 60;
    const hh = h < 10 ? `0${h}` : `${h}`;
    const mm = m < 10 ? `0${m}` : `${m}`;
    return `${hh}:${mm}`;
  }

  private barHeight(val: number): number {
    if (val <= 0 || this.maxHourlySteps <= 0) {
      return 2;
    }
    return Math.max(4, Math.round((val / this.maxHourlySteps) * 112));
  }

  private glucoseLevelText(level: number): string {
    switch (level) {
      case 1: return '（偏低）';
      case 2: return '（中等）';
      case 3: return '（偏高）';
      default: return '';
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('日常数据').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        if (this.querying) {
          Text(this.progressText ? this.progressText : '查询中').fontSize(13).fontColor('#007DFF')
        }
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      // 日期选择（分段控件）
      Row() {
        this.DayTab(HealthQueryDay.TODAY, '今天')
        this.DayTab(HealthQueryDay.YESTERDAY, '昨天')
        this.DayTab(HealthQueryDay.DAY_BEFORE_YESTERDAY, '前天')
      }
      .width('100%').backgroundColor('#ECECEC').borderRadius(8)
      .padding(3).margin({ left: 16, right: 16, top: 12 })

      // 查询进度条
      if (this.querying) {
        Progress({ value: this.progressPct, total: 100, type: ProgressType.Linear })
          .width('100%').margin({ left: 16, right: 16, top: 12 })
          .color('#007DFF').backgroundColor('#E5E5E5').borderRadius(2)
      }

      // 内容区
      Scroll() {
        Column() {
          if (this.hasData) {
            this.SummaryCard()
            this.ActivityCard()
            this.HeartRateCard()
            this.VitalsCard()
          } else {
            this.Placeholder()
          }
        }.width('100%').padding({ bottom: 24 })
      }
      .width('100%').layoutWeight(1).align(Alignment.Top)
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  DayTab(day: HealthQueryDay, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.hasQueried && this.selectedDay === day ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.hasQueried && this.selectedDay === day ? Color.White : '#666666')
      .backgroundColor(this.hasQueried && this.selectedDay === day ? '#007DFF' : Color.Transparent)
      .borderRadius(6)
      .height(34)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .opacity(this.querying ? 0.5 : 1)
      .onClick(() => this.queryHealthData(day))
  }

  @Builder
  Placeholder() {
    Column() {
      Text(this.querying ? `正在查询日常数据... ${this.progressText}` : (this.logMsg || '请选择日期查看日常健康数据'))
        .fontSize(14)
        .fontColor(this.hasError ? '#FF3B30' : '#999999')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .padding({ top: 96, bottom: 96 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SummaryCard() {
    Column() {
      Text('运动汇总').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ bottom: 12 })
      Row() {
        this.MetricCol('步数', `${this.totalSteps}`, '#007DFF', '步')
        this.MetricCol('距离', `${this.totalDistance.toFixed(2)}`, '#34C759', 'km')
        this.MetricCol('热量', `${this.totalCalories.toFixed(0)}`, '#FF9500', 'kcal')
      }.width('100%')

      Divider().color('#F0F0F0').margin({ top: 14, bottom: 14 })

      Row() {
        Column() {
          Text('数据点').fontSize(11).fontColor('#999999')
          Text(`${this.slotCount} 个`).fontSize(14).fontColor('#333333').margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column() {
          Text('时间范围').fontSize(11).fontColor('#999999')
          Text(`${this.timeStart} - ${this.timeEnd}`).fontSize(14).fontColor('#333333').margin({ top: 2 })
        }.alignItems(HorizontalAlign.End)
      }.width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  ActivityCard() {
    Column() {
      Row() {
        Text('活动趋势（按小时）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        if (this.maxHourlySteps > 0) {
          Text(`峰值 ${this.maxHourlySteps} 步`).fontSize(11).fontColor('#999999')
        }
      }.width('100%').margin({ bottom: 12 })

      // 24 小时步数柱状图
      Row() {
        ForEach(this.hourlySteps, (val: number, h: number) => {
          Column()
            .layoutWeight(1)
            .height(this.barHeight(val))
            .backgroundColor(val > 0 ? (h === this.peakHour ? '#FF9500' : '#007DFF') : '#E8E8E8')
            .borderRadius(2)
        }, (val: number, h: number) => `${h}`)
      }
      .width('100%').height(120)
      .alignItems(VerticalAlign.Bottom)

      // x 轴刻度
      Row() {
        Text('00').fontSize(10).fontColor('#BBBBBB')
        Text('06').fontSize(10).fontColor('#BBBBBB')
        Text('12').fontSize(10).fontColor('#BBBBBB')
        Text('18').fontSize(10).fontColor('#BBBBBB')
        Text('24').fontSize(10).fontColor('#BBBBBB')
      }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 6 })

      if (this.peakHour >= 0) {
        Text(`活动高峰 ${this.peakHour}:00 — ${this.maxHourlySteps} 步`)
          .fontSize(11).fontColor('#666666').margin({ top: 8 })
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  HeartRateCard() {
    Column() {
      Text('心率').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ bottom: 12 })
      Row() {
        this.MetricCol('平均', this.hrAvg > 0 ? `${this.hrAvg}` : '--', '#FF3B30', 'bpm')
        this.MetricCol('最高', this.hrMax > 0 ? `${this.hrMax}` : '--', '#FF9500', 'bpm')
        this.MetricCol('最低', this.hrMin > 0 ? `${this.hrMin}` : '--', '#5856D6', 'bpm')
      }.width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  VitalsCard() {
    Column() {
      Text('健康指标').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ bottom: 4 })
      this.MetricRow('血氧', this.spo2Avg > 0 ? `${this.spo2Avg} %` : '--')
      this.MetricRow('血压', (this.bpSys > 0 && this.bpDia > 0) ? `${this.bpSys}/${this.bpDia} mmHg` : '--')
      this.MetricRow('体温', this.bodyTemp > 0 ? `${this.bodyTemp.toFixed(1)} ℃` : '--')
      this.MetricRow('血糖', this.bloodGlucose > 0
        ? `${this.bloodGlucose.toFixed(2)} mmol/L${this.glucoseLevelText(this.bloodGlucoseLevel)}` : '--')
      this.MetricRow('压力', this.stressAvg > 0 ? `${this.stressAvg}` : '--')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  @Builder
  MetricCol(label: string, value: string, color: string, unit: string) {
    Column() {
      Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor(color)
      Row() {
        Text(label).fontSize(11).fontColor('#999999')
        if (unit !== '') {
          Text(` · ${unit}`).fontSize(11).fontColor('#BBBBBB')
        }
      }.margin({ top: 2 })
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
  }

  @Builder
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#333333')
    }.width('100%').height(40)
  }
}

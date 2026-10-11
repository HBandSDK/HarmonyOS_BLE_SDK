import { router } from '@kit.ArkUI';
import { VPBleSDK, HealthQueryDay, HealthData, DailyFiveData } from '@veepoo/vpble-sdk';

// 图表：24 小时分桶 + 图表区高度
const CHART_SLOTS = 24;
const CHART_HEIGHT = 120;

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

  // 按小时趋势（24 点，0 表示该小时无数据）
  @State hourlySteps: number[] = [];
  @State maxHourlySteps: number = 0;
  @State hourlyHr: number[] = [];
  @State hourlySpo2: number[] = [];
  @State hourlyStress: number[] = [];
  @State hourlyBpSys: number[] = [];
  @State hourlyBpDia: number[] = [];
  @State hourlyTemp: number[] = [];
  @State hourlyGlucose: number[] = [];

  // 心率（由 ecgs 聚合）
  @State hrAvg: number = 0;
  @State hrMax: number = 0;
  @State hrMin: number = 0;

  // 健康指标（血压/体温/血糖为当天最近一次测量值）
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

  // 由 5 分钟分片聚合成日级展示数据（含按小时图表分桶）
  private computeAggregates(data: HealthData): void {
    // sportSummary 为协议原始值（距离=米 / 热量=0.1kcal，见 DfHealthDataParser），此处换算为 km / kcal
    this.totalSteps = data.sportSummary.totalSteps;
    this.totalDistance = data.sportSummary.totalDistance / 1000;
    this.totalCalories = data.sportSummary.totalCalories / 10;

    // 按时间升序，便于取“最新”值与时间范围
    const slots: DailyFiveData[] = data.fiveMinuteData.slice()
      .sort((a: DailyFiveData, b: DailyFiveData) => a.time - b.time);
    this.slotCount = slots.length;

    const validTimes: number[] = slots
      .filter((s: DailyFiveData) => s.time !== 0xFFFF && s.time <= 1435)
      .map((s: DailyFiveData) => s.time);
    this.timeStart = validTimes.length > 0 ? this.minToHHmm(validTimes[0]) : '--:--';
    this.timeEnd = validTimes.length > 0 ? this.minToHHmm(validTimes[validTimes.length - 1]) : '--:--';

    // 按小时分桶：步数累加；心率/血氧/压力取小时均值；血压/体温/血糖取该小时最后一次测量值
    const hourly: number[] = new Array<number>(24).fill(0);
    const hrSumH = new Array<number>(24).fill(0);
    const hrCntH = new Array<number>(24).fill(0);
    const spo2SumH = new Array<number>(24).fill(0);
    const spo2CntH = new Array<number>(24).fill(0);
    const stressSumH = new Array<number>(24).fill(0);
    const stressCntH = new Array<number>(24).fill(0);
    const bpSysH = new Array<number>(24).fill(0);
    const bpDiaH = new Array<number>(24).fill(0);
    const tempH = new Array<number>(24).fill(0);
    const glucoseH = new Array<number>(24).fill(0);

    // 全天聚合
    let hrSum = 0, hrCnt = 0, hrMax = 0, hrMin = 999;
    let spo2Sum = 0, spo2Cnt = 0;
    let stressSum = 0, stressCnt = 0;
    let bpS = 0, bpD = 0;
    let temp = 0;
    let glucose = 0, glucoseLevel = 0;

    for (const s of slots) {
      const h = (s.time !== 0xFFFF && s.time <= 1435) ? Math.floor(s.time / 60) : -1;

      if (h >= 0 && h < 24) {
        hourly[h] += s.steps;
      }

      for (const v of this.pickHrValues(s)) {
        if (v > 0) {
          hrSum += v;
          hrCnt++;
          if (v > hrMax) hrMax = v;
          if (v < hrMin) hrMin = v;
          if (h >= 0 && h < 24) {
            hrSumH[h] += v;
            hrCntH[h]++;
          }
        }
      }
      for (const v of s.spO2Values) {
        if (v > 0 && v <= 100) {
          spo2Sum += v;
          spo2Cnt++;
          if (h >= 0 && h < 24) {
            spo2SumH[h] += v;
            spo2CntH[h]++;
          }
        }
      }
      if (s.stress > 0) {
        stressSum += s.stress;
        stressCnt++;
        if (h >= 0 && h < 24) {
          stressSumH[h] += s.stress;
          stressCntH[h]++;
        }
      }
      if (s.systolicBP > 0 && s.diastolicBP > 0) {
        bpS = s.systolicBP;
        bpD = s.diastolicBP;
        if (h >= 0 && h < 24) {
          bpSysH[h] = s.systolicBP;
          bpDiaH[h] = s.diastolicBP;
        }
      }
      if (s.bodyTemp > 0) {
        temp = s.bodyTemp;
        if (h >= 0 && h < 24) {
          tempH[h] = s.bodyTemp;
        }
      }
      if (s.bloodGlucose > 0) {
        glucose = s.bloodGlucose;
        glucoseLevel = s.bloodGlucoseLevel;
        if (h >= 0 && h < 24) {
          glucoseH[h] = s.bloodGlucose;
        }
      }
    }

    this.hourlySteps = hourly;
    let maxH = 0;
    for (let hh = 0; hh < 24; hh++) {
      if (hourly[hh] > maxH) {
        maxH = hourly[hh];
      }
    }
    this.maxHourlySteps = maxH;

    // 小时均值
    const hrHourly = new Array<number>(24).fill(0);
    const spo2Hourly = new Array<number>(24).fill(0);
    const stressHourly = new Array<number>(24).fill(0);
    for (let hh = 0; hh < 24; hh++) {
      hrHourly[hh] = hrCntH[hh] > 0 ? Math.round(hrSumH[hh] / hrCntH[hh]) : 0;
      spo2Hourly[hh] = spo2CntH[hh] > 0 ? Math.round(spo2SumH[hh] / spo2CntH[hh]) : 0;
      stressHourly[hh] = stressCntH[hh] > 0 ? Math.round(stressSumH[hh] / stressCntH[hh]) : 0;
    }
    this.hourlyHr = hrHourly;
    this.hourlySpo2 = spo2Hourly;
    this.hourlyStress = stressHourly;
    this.hourlyBpSys = bpSysH.slice();
    this.hourlyBpDia = bpDiaH.slice();
    this.hourlyTemp = tempH.slice();
    this.hourlyGlucose = glucoseH.slice();

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

  // 心率来源：ECG 与 PPG 不会同时有值，哪个有值取哪个
  private pickHrValues(s: DailyFiveData): number[] {
    for (const v of s.ecgs) {
      if (v > 0) {
        return s.ecgs;
      }
    }
    return s.ppgs;
  }

  private minToHHmm(min: number): string {
    const h = Math.floor(min / 60);
    const m = min % 60;
    const hh = h < 10 ? `0${h}` : `${h}`;
    const mm = m < 10 ? `0${m}` : `${m}`;
    return `${hh}:${mm}`;
  }

  private glucoseLevelText(level: number): string {
    switch (level) {
      case 1: return '（偏低）';
      case 2: return '（中等）';
      case 3: return '（偏高）';
      default: return '';
    }
  }

  // 光标图例文案（'' 表示该小时无数据）
  private simpleTips(values: number[]): string[] {
    const tips: string[] = [];
    for (const v of values) {
      tips.push(v > 0 ? `${v}` : '');
    }
    return tips;
  }

  private decimalTips(values: number[], digits: number): string[] {
    const tips: string[] = [];
    for (const v of values) {
      tips.push(v > 0 ? v.toFixed(digits) : '');
    }
    return tips;
  }

  private bpTips(): string[] {
    const tips: string[] = [];
    for (let h = 0; h < 24; h++) {
      tips.push(this.hourlyBpSys[h] > 0 ? `${this.hourlyBpSys[h]}/${this.hourlyBpDia[h]}` : '');
    }
    return tips;
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
            TrendCard({
              title: '活动趋势（按小时）',
              summary: this.maxHourlySteps > 0 ? `峰值 ${this.maxHourlySteps} 步` : '',
              values: this.hourlySteps,
              tooltips: this.simpleTips(this.hourlySteps),
              unit: ' 步',
              color: '#007DFF'
            })
            TrendCard({
              title: '心率趋势',
              summary: this.hrAvg > 0 ? `平均 ${this.hrAvg} · 最高 ${this.hrMax} · 最低 ${this.hrMin} bpm` : '',
              values: this.hourlyHr,
              tooltips: this.simpleTips(this.hourlyHr),
              unit: ' bpm',
              color: '#FF3B30'
            })
            TrendCard({
              title: '血氧趋势',
              summary: this.spo2Avg > 0 ? `平均 ${this.spo2Avg} %` : '',
              values: this.hourlySpo2,
              tooltips: this.simpleTips(this.hourlySpo2),
              unit: ' %',
              color: '#34C759'
            })
            TrendCard({
              title: '血压趋势',
              summary: (this.bpSys > 0 && this.bpDia > 0) ? `最近 ${this.bpSys}/${this.bpDia} mmHg` : '',
              values: this.hourlyBpSys,
              tooltips: this.bpTips(),
              unit: ' mmHg',
              color: '#5856D6'
            })
            TrendCard({
              title: '体温趋势',
              summary: this.bodyTemp > 0 ? `最近 ${this.bodyTemp.toFixed(1)} ℃` : '',
              values: this.hourlyTemp,
              tooltips: this.decimalTips(this.hourlyTemp, 1),
              unit: ' ℃',
              color: '#FF9500'
            })
            TrendCard({
              title: '血糖趋势',
              summary: this.bloodGlucose > 0
                ? `最近 ${this.bloodGlucose.toFixed(2)} mmol/L${this.glucoseLevelText(this.bloodGlucoseLevel)}` : '',
              values: this.hourlyGlucose,
              tooltips: this.decimalTips(this.hourlyGlucose, 2),
              unit: ' mmol/L',
              color: '#AF52DE'
            })
            TrendCard({
              title: '压力趋势',
              summary: this.stressAvg > 0 ? `平均 ${this.stressAvg}` : '',
              values: this.hourlyStress,
              tooltips: this.simpleTips(this.hourlyStress),
              unit: '',
              color: '#FF2D55'
            })
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
        this.MetricCol('距离', `${this.totalDistance.toFixed(3)}`, '#34C759', 'km')
        this.MetricCol('热量', `${this.totalCalories.toFixed(1)}`, '#FF9500', 'kcal')
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
}

// 通用趋势卡片：24 小时柱状图，点击出现光标，图例展示光标所在小时的数据
@Component
struct TrendCard {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop @Watch('onValuesChange') values: number[] = [];
  @Prop tooltips: string[] = [];
  @Prop unit: string = '';
  @Prop color: string = '#007DFF';
  @State cursorIndex: number = -1;
  @State draggingX: number = -1; // 拖动中光标的连续像素位置（-1 表示未在拖动）
  @State chartWidth: number = 0;
  private panStartX: number = 0;
  private touchDownX: number = 0;

  onValuesChange() {
    // 数据切换（换天/新查询）后隐藏旧光标
    this.cursorIndex = -1;
    this.draggingX = -1;
  }

  private maxValue(): number {
    let max = 0;
    for (const v of this.values) {
      if (v > max) {
        max = v;
      }
    }
    return max;
  }

  private barHeight(val: number): number {
    const max = this.maxValue();
    if (val <= 0 || max <= 0) {
      return 2;
    }
    return Math.max(4, Math.round((val / max) * (CHART_HEIGHT - 8)));
  }

  private slotWidth(): number {
    return this.chartWidth / CHART_SLOTS;
  }

  private clampIndex(x: number): number {
    let idx = Math.floor(x / this.slotWidth());
    if (idx < 0) {
      idx = 0;
    }
    if (idx > CHART_SLOTS - 1) {
      idx = CHART_SLOTS - 1;
    }
    return idx;
  }

  // 当前生效的小时：拖动中实时跟随手指，否则为吸附后的小时
  private displayIndex(): number {
    return this.draggingX >= 0 ? this.clampIndex(this.draggingX) : this.cursorIndex;
  }

  private lineX(): number {
    if (this.draggingX >= 0) {
      return this.draggingX - 1;
    }
    const slot = this.slotWidth();
    return this.cursorIndex * slot + slot / 2 - 1;
  }

  private cursorValueText(): string {
    const idx = this.displayIndex();
    if (idx < 0 || idx >= this.tooltips.length) {
      return '--';
    }
    const tip = this.tooltips[idx];
    return tip === '' ? '无数据' : `${tip}${this.unit}`;
  }

  build() {
    Column() {
      // 标题 + 摘要
      Row() {
        Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        if (this.summary !== '') {
          Text(this.summary).fontSize(11).fontColor('#999999')
        }
      }.width('100%').margin({ bottom: 8 })

      // 光标图例：展示光标所在小时的数据
      Row() {
        if (this.displayIndex() >= 0) {
          Text(`${this.displayIndex()}:00 - ${this.displayIndex() + 1}:00`)
            .fontSize(11).fontColor('#666666').margin({ right: 8 })
          Text(this.cursorValueText())
            .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.color)
        } else {
          Text('点击或左右拖动查看数据').fontSize(11).fontColor('#BBBBBB')
        }
      }.width('100%').height(18).margin({ bottom: 4 })

      // 图表：柱状图 + 光标竖线
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          ForEach(this.values, (val: number, h: number) => {
            Column()
              .layoutWeight(1)
              .height(this.barHeight(val))
              .backgroundColor(val > 0 ? this.color : '#E8E8E8')
              .borderRadius(2)
              .margin({ left: 1.5, right: 1.5 })
          }, (val: number, h: number) => `${h}_${val}_${this.maxValue()}`)
        }
        .width('100%').height('100%')
        .alignItems(VerticalAlign.Bottom)

        if (this.displayIndex() >= 0 && this.chartWidth > 0) {
          Column()
            .width(2)
            .height('100%')
            .backgroundColor('#66000000')
            .position({ x: this.lineX(), y: 0 })
        }
      }
      .width('100%').height(CHART_HEIGHT)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.touchDownX = Number(event.touches[0].x);
        }
      })
      .onClick((event: ClickEvent) => {
        // 点击：光标吸附到所点小时；再次点击同一位置隐藏
        if (this.chartWidth <= 0) {
          return;
        }
        const idx = this.clampIndex(event.x);
        this.cursorIndex = this.cursorIndex === idx ? -1 : idx;
      })
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
        .onActionStart(() => {
          if (this.chartWidth <= 0) {
            return;
          }
          // 无光标时先在按下位置显示，再进入拖动
          if (this.cursorIndex < 0) {
            this.cursorIndex = this.clampIndex(this.touchDownX);
          }
          const slot = this.slotWidth();
          this.panStartX = this.cursorIndex * slot + slot / 2;
          this.draggingX = this.panStartX;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.chartWidth <= 0) {
            return;
          }
          let x = this.panStartX + event.offsetX;
          if (x < 0) {
            x = 0;
          }
          if (x > this.chartWidth) {
            x = this.chartWidth;
          }
          this.draggingX = x;
        })
        .onActionEnd(() => {
          if (this.draggingX >= 0) {
            this.cursorIndex = this.clampIndex(this.draggingX);
            this.draggingX = -1;
          }
        }))
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.chartWidth = Number(newValue.width);
      })

      // x 轴刻度
      Row() {
        Text('00').fontSize(10).fontColor('#BBBBBB')
        Text('06').fontSize(10).fontColor('#BBBBBB')
        Text('12').fontSize(10).fontColor('#BBBBBB')
        Text('18').fontSize(10).fontColor('#BBBBBB')
        Text('24').fontSize(10).fontColor('#BBBBBB')
      }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 6 })
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }
}

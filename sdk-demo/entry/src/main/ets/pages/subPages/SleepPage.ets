import { router } from '@kit.ArkUI';
import { VPBleSDK, HealthQueryDay, AccurateSleepModel } from '@veepoo/vpble-sdk';

/** 睡眠曲线解析后的连续同阶段片段 */
interface SleepStageBlock {
  /** 阶段: 0=深睡 1=浅睡 2=REM 3=失眠 4=清醒 */
  stage: number;
  /** 连续点数（每点 = onePointDuration 秒） */
  count: number;
}

@Entry
@Component
struct SleepPage {
  @State segments: AccurateSleepModel[] = [];
  @State curves: SleepStageBlock[][] = [];
  @State selectedDay: HealthQueryDay = HealthQueryDay.TODAY;
  @State hasQueried: boolean = false;
  @State querying: boolean = false;
  @State hasError: boolean = false;
  @State logMsg: string = '';

  // 睡眠阶段配色（与图例/曲线/分项统一）
  private readonly STAGE_DEEP_COLOR: string = '#5856D6';
  private readonly STAGE_LIGHT_COLOR: string = '#4AA3FF';
  private readonly STAGE_REM_COLOR: string = '#34C759';
  private readonly STAGE_AWAKE_COLOR: string = '#FF9500';
  private readonly STAGE_INSOMNIA_COLOR: string = '#FF3B30';
  private readonly STAGE_OTHER_COLOR: string = '#D8D8D8';

  private querySleep(day: HealthQueryDay): void {
    if (this.querying) {
      return;
    }
    this.querying = true;
    this.hasQueried = true;
    this.selectedDay = day;
    this.hasError = false;
    this.logMsg = '';
    this.segments = [];
    this.curves = [];
    VPBleSDK.getInstance().healthService.getSleepData(day).then((result) => {
      const data = result.data;
      if (result.success && data && data.length > 0) {
        this.segments = data;
        this.curves = data.map((seg: AccurateSleepModel) => this.parseSleepLine(seg.sleepLine));
      } else if (result.success) {
        this.logMsg = '当天无睡眠数据';
      } else {
        this.hasError = true;
        this.logMsg = `查询失败: ${result.errorMessage ?? '未知错误'}`;
      }
    }).catch((err: Error) => {
      this.hasError = true;
      this.logMsg = `错误: ${err.message}`;
    }).finally(() => {
      this.querying = false;
    });
  }

  // sleepLine 十六进制串按 SDK 约定的编码规则还原为连续同阶段片段
  private parseSleepLine(sleepLine: string): SleepStageBlock[] {
    const blocks: SleepStageBlock[] = [];
    if (!sleepLine || sleepLine.length < 4) {
      return blocks;
    }
    let prevStage: number = -1;
    for (let i = 0; i + 3 < sleepLine.length; i += 4) {
      const highByte = parseInt(sleepLine.substring(i, i + 2), 16);
      const stage = (highByte >> 5) & 0x07;
      if (stage === prevStage && blocks.length > 0) {
        blocks[blocks.length - 1].count += 1;
      } else {
        blocks.push({ stage: stage, count: 1 });
        prevStage = stage;
      }
    }
    return blocks;
  }

  private stageColor(stage: number): string {
    switch (stage) {
      case 0: return this.STAGE_DEEP_COLOR;
      case 1: return this.STAGE_LIGHT_COLOR;
      case 2: return this.STAGE_REM_COLOR;
      case 3: return this.STAGE_INSOMNIA_COLOR;
      case 4: return this.STAGE_AWAKE_COLOR;
      default: return this.STAGE_OTHER_COLOR;
    }
  }

  private formatDuration(min: number): string {
    if (min <= 0) {
      return '0分钟';
    }
    const h = Math.floor(min / 60);
    const m = min % 60;
    if (h <= 0) {
      return `${m}分钟`;
    }
    if (m === 0) {
      return `${h}小时`;
    }
    return `${h}小时${m}分`;
  }

  // 分钟时长，0 显示占位
  private dur(min: number): string {
    return min > 0 ? this.formatDuration(min) : '--';
  }

  // yyyy-MM-dd HH:mm → HH:mm
  private formatClock(time: string): string {
    if (!time) {
      return '--:--';
    }
    const idx = time.indexOf(' ');
    return idx >= 0 ? time.substring(idx + 1) : time;
  }

  // yyyy-MM-dd HH:mm → yyyy-MM-dd
  private formatDate(time: string): string {
    if (!time) {
      return '';
    }
    const idx = time.indexOf(' ');
    return idx >= 0 ? time.substring(0, idx) : '';
  }

  // sleepQuality 0~4 → ★/☆ 1~5 星
  private stars(quality: number): string {
    const n = Math.max(0, Math.min(5, quality + 1));
    return '★★★★★'.substring(0, n) + '☆☆☆☆☆'.substring(0, 5 - n);
  }

  private accurateTypeText(t: number): string {
    switch (t) {
      case 1: return '精准';
      case 2: return '中科';
      default: return '普通';
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('睡眠').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        if (this.querying) {
          Text('查询中').fontSize(13).fontColor('#999999')
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

      // 内容区
      Scroll() {
        Column() {
          if (this.segments.length > 0) {
            ForEach(this.segments, (seg: AccurateSleepModel, idx: number) => {
              this.SleepCard(seg, this.curves[idx], idx)
            }, (seg: AccurateSleepModel, idx: number) => `${idx}`)
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
      .onClick(() => this.querySleep(day))
  }

  @Builder
  Placeholder() {
    Column() {
      Text(this.querying ? '正在查询睡眠数据...' : (this.logMsg || '请选择日期查看睡眠数据'))
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
  SleepCard(seg: AccurateSleepModel, blocks: SleepStageBlock[], index: number) {
    Column() {
      // 卡片头：序号 + 睡眠类型
      Row() {
        Text(this.segments.length > 1 ? `睡眠 ${index + 1}` : '睡眠数据')
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        Text(this.accurateTypeText(seg.accurateType))
          .fontSize(11)
          .fontColor(seg.accurateType === 0 ? '#999999' : '#5856D6')
          .backgroundColor(seg.accurateType === 0 ? '#F2F2F2' : '#F0EEFF')
          .borderRadius(10)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      }.width('100%')

      // 入睡/清醒时段 + 星级
      Row() {
        Column() {
          Row() {
            Text(this.formatClock(seg.sleepTime)).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#333333')
            Text(' → ').fontSize(14).fontColor('#BBBBBB')
            Text(this.formatClock(seg.wakeTime)).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#333333')
          }
          if (this.formatDate(seg.sleepTime)) {
            Text(this.formatDate(seg.sleepTime)).fontSize(11).fontColor('#999999').margin({ top: 2 })
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

        Column() {
          Text(this.stars(seg.sleepQuality)).fontSize(16).fontColor('#FF9500')
          Text(`睡眠质量 ${seg.sleepQuality + 1} 星`).fontSize(11).fontColor('#999999').margin({ top: 2 })
        }.alignItems(HorizontalAlign.End)
      }.width('100%').margin({ top: 14 })

      // 总睡眠时长（hero）
      Column() {
        Text(this.dur(seg.sleepDuration)).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#333333')
        Text('总睡眠时长').fontSize(12).fontColor('#999999').margin({ top: 2 })
      }.width('100%').alignItems(HorizontalAlign.Center).margin({ top: 16 })

      // 睡眠曲线
      if (blocks.length > 0) {
        Column() {
          Text('睡眠曲线').fontSize(12).fontColor('#999999').width('100%').margin({ bottom: 8 })
          Row() {
            ForEach(blocks, (b: SleepStageBlock, i: number) => {
              Column()
                .layoutWeight(b.count)
                .height(10)
                .backgroundColor(this.stageColor(b.stage))
            }, (b: SleepStageBlock, i: number) => `${index}-${i}-${b.stage}-${b.count}`)
          }.width('100%').borderRadius(5).clip(true)

          // 图例
          Row() {
            this.LegendDot(this.STAGE_DEEP_COLOR, '深睡')
            this.LegendDot(this.STAGE_LIGHT_COLOR, '浅睡')
            this.LegendDot(this.STAGE_REM_COLOR, 'REM')
            this.LegendDot(this.STAGE_AWAKE_COLOR, '清醒')
            this.LegendDot(this.STAGE_INSOMNIA_COLOR, '失眠')
          }.width('100%').margin({ top: 8 })
        }.width('100%').margin({ top: 18 })
      }

      // 各阶段时长
      Row() {
        this.StageCell('深睡', this.dur(seg.deepDuration), this.STAGE_DEEP_COLOR)
        this.StageCell('浅睡', this.dur(seg.lightDuration), this.STAGE_LIGHT_COLOR)
        this.StageCell('REM', this.dur(seg.otherDuration), this.STAGE_REM_COLOR)
        this.StageCell('清醒', this.dur(seg.getUpDuration), this.STAGE_AWAKE_COLOR)
      }.width('100%').margin({ top: 16 })

      // 明细
      Column() {
        this.MetricRow('夜间起床', seg.getUpTimes > 0 ? `${seg.getUpTimes} 次` : '--')
        this.MetricRow('入睡到首次深睡', this.dur(seg.firstDeepDuration))
        this.MetricRow('睡眠效率', seg.sleepEfficiencyScore > 0 ? `${seg.sleepEfficiencyScore} 分` : '--')
        this.MetricRow('深睡评分', seg.deepScore > 0 ? `${seg.deepScore} 分` : '--')
      }.width('100%').margin({ top: 6 })
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  LegendDot(color: string, label: string) {
    Row() {
      Row().width(8).height(8).backgroundColor(color).borderRadius(4)
      Text(label).fontSize(10).fontColor('#999999').margin({ left: 4 })
    }.layoutWeight(1).alignItems(VerticalAlign.Center)
  }

  @Builder
  StageCell(label: string, value: string, color: string) {
    Column() {
      Text(label).fontSize(11).fontColor('#999999')
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor(color).margin({ top: 4 })
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
  }

  @Builder
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#333333')
    }.width('100%').height(38)
  }
}

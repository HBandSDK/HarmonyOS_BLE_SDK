import { router } from '@kit.ArkUI';
import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import {
  VPBleSDK,
  HealthQueryDay,
  HrvScatterResult,
  HrvStarIndexResult,
  HrvSimilarityResult,
} from '@veepoo/vpble-sdk';
import { HrvWorkerRequest, HrvWorkerResponse } from '../../workers/HrvWorkers';

/**
 * 门控验证（内部调试页）
 *
 * 验证 SDK 授权门控的三个数据出口。设备授权态由连接期 SDK 自动与
 * 授权服务器交互决定，运行日志中会输出当前设备各功能的授权结果。
 *
 *  1. 血氧附加字段（综合日常数据读取的门控出口，对齐 iOS）：
 *     未授权 → 只有血氧值本身，呼吸暂停/缺氧/心脏负荷/血氧校正等附加数组不返回；
 *  2. HRV 洛伦兹（HrvAnalyzer 本地计算，选定天读取——每天一份 RR 一个图，与手环 App 一致）：
 *     未授权 → 日常数据出口已剥离 RR（全天 RR=0）；有 RR 时 getScatterPlot
 *     返回 control=0 + 空结果（与数据量无关），两出口构成双门控；
 *     星级/相似度不受门控，作对照组（注意各自数据量门槛，不足时也是 control=1 + 空结果）；
 *     ★ 三件套是重计算，必须经 Worker 子线程执行（workers/HrvWorkers），UI 线程直调会卡死；
 *  3. ECG 诊断：未授权 → 波形/进度正常，但收尾诊断结果事件不下发（见「ECG心电」页）。
 */

/** 单天三件套计算结果（worker JSON 反序列化后） */
interface HrvDayResults {
  scatter: HrvScatterResult;
  star: HrvStarIndexResult;
  similarity: HrvSimilarityResult;
}
@Entry
@Component
struct GatingDebugPage {
  // ---- 全天血氧 ----
  @State spo2Day: number = 0;
  @State spo2Querying: boolean = false;
  @State spo2Count: number = 0;
  @State spo2ExtraNonZero: number = -1; // 附加字段非零的条目数（-1=未查询）
  @State spo2RawLines: string[] = [];
  @State spo2Msg: string = '';

  // ---- HRV 散点（按天独立计算，与手环 App 一致：每天一份 RR 一个图）----
  @State hrvDay: number = 0;
  @State hrvRing: boolean = false;
  @State hrvQuerying: boolean = false;
  @State hrvProgressText: string = '';
  @State hrvDayBlocks: string[] = [];
  @State hrvMsg: string = '';
  private _hrvWorker: worker.ThreadWorker | null = null;

  aboutToDisappear(): void {
    if (this._hrvWorker !== null) {
      this._hrvWorker.terminate();
      this._hrvWorker = null;
    }
  }

  private _ensureHrvWorker(): worker.ThreadWorker {
    if (this._hrvWorker === null) {
      this._hrvWorker = new worker.ThreadWorker('entry/ets/workers/HrvWorkers.ets');
    }
    return this._hrvWorker;
  }

  /** 三件套重计算派发到 Worker 子线程（UI 线程直调会卡死页面）；一次一请求，顺序回包 */
  private computeHrvInWorker(rr: number[], isRing: boolean): Promise<HrvDayResults> {
    return new Promise<HrvDayResults>((resolve, reject) => {
      let wk: worker.ThreadWorker;
      try {
        wk = this._ensureHrvWorker();
      } catch (err) {
        reject(err as Error);
        return;
      }
      wk.onmessage = (e: MessageEvents) => {
        try {
          const resp = JSON.parse(e.data) as HrvWorkerResponse;
          resolve({
            scatter: JSON.parse(resp.scatter) as HrvScatterResult,
            star: JSON.parse(resp.star) as HrvStarIndexResult,
            similarity: JSON.parse(resp.similarity) as HrvSimilarityResult,
          });
        } catch (err) {
          reject(err as Error);
        }
      };
      wk.onerror = (e: ErrorEvent) => {
        reject(new Error(`worker 异常: ${e.message}`));
      };
      const req: HrvWorkerRequest = { data: rr, isRingDevice: isRing };
      wk.postMessage(JSON.stringify(req));
    });
  }

  private dayToHealthQuery(day: number): HealthQueryDay {
    if (day === 1) {
      return HealthQueryDay.YESTERDAY;
    }
    if (day === 2) {
      return HealthQueryDay.DAY_BEFORE_YESTERDAY;
    }
    return HealthQueryDay.TODAY;
  }

  // ==================== 血氧附加字段（日常数据出口） ====================
  private queryAllDaySpo2(): void {
    if (this.spo2Querying) {
      return;
    }
    this.spo2Querying = true;
    this.spo2RawLines = [];
    this.spo2ExtraNonZero = -1;
    this.spo2Msg = '读取中...';
    // 血氧附加字段的门控出口在综合日常数据读取（对齐 iOS）：未授权只给血氧值本身，
    // 呼吸暂停/缺氧/心脏负荷/血氧校正等附加数组不返回
    VPBleSDK.getInstance().healthService
      .getHealthData(this.dayToHealthQuery(this.spo2Day), 1, (progress: number) => {
        this.spo2Msg = `读取中 ${Math.round(progress * 100)}%`;
      })
      .then((result) => {
        const data = result.data;
        if (!result.success || !data) {
          this.spo2Msg = `读取失败: ${result.errorMessage ?? '未知错误'}`;
          return;
        }
        let slotCount = data.fiveMinuteData.length;
        let validSlots = 0;
        let extrasNonZero = 0;
        const dump: string[] = [];
        for (const s of data.fiveMinuteData) {
          const hasSpo2 = s.spO2Values.some((v: number) => v > 0);
          const hasExtras = s.apneaTimes.some((v: number) => v > 0) ||
            s.apneaResults.some((v: number) => v > 0) ||
            s.anoxicTimes.some((v: number) => v > 0) ||
            s.cardiacLoads.some((v: number) => v > 0) ||
            s.oxygenCorrections.some((v: number) => v > 0);
          if (hasSpo2) {
            validSlots++;
            if (dump.length < 3) {
              dump.push(`${this.minToHHmm(s.time)} spO2=[${s.spO2Values.join(',')}] ` +
                `呼吸暂停=[${s.apneaTimes.join(',')}/${s.apneaResults.join(',')}] ` +
                `缺氧=[${s.anoxicTimes.join(',')}] 负荷=[${s.cardiacLoads.join(',')}] ` +
                `校正=[${s.oxygenCorrections.join(',')}]`);
            }
          }
          if (hasExtras) {
            extrasNonZero++;
          }
        }
        this.spo2Count = slotCount;
        this.spo2ExtraNonZero = extrasNonZero;
        this.spo2RawLines = dump;
        if (validSlots === 0) {
          this.spo2Msg = `5 分钟片 ${slotCount} 个均无血氧值，该天没有有效测量数据`;
        } else if (extrasNonZero > 0) {
          this.spo2Msg = `5 分钟片 ${slotCount}（有效血氧 ${validSlots}），附加字段非零片 ${extrasNonZero}` +
            `（授权放行形态；对照未授权态应为 0）`;
        } else {
          this.spo2Msg = `5 分钟片 ${slotCount}（有效血氧 ${validSlots}），附加字段全空` +
            `（未授权剥离形态；若设备端本就无附加数据，需与授权态对照后判断）`;
        }
      })
      .catch((err: Error) => {
        this.spo2Msg = `错误: ${err.message}`;
      })
      .finally(() => {
        this.spo2Querying = false;
      });
  }

  private minToHHmm(min: number): string {
    const h = Math.floor(min / 60) % 24;
    const m = min % 60;
    return `${h < 10 ? '0' + h : h}:${m < 10 ? '0' + m : m}`;
  }

  // ==================== HRV 散点（选定天独立计算） ====================
  private async queryHrvScatter(): Promise<void> {
    if (this.hrvQuerying) {
      return;
    }
    this.hrvQuerying = true;
    this.hrvDayBlocks = [];
    this.hrvMsg = '读取中...';
    const dayLabels: string[] = ['今天', '昨天', '前天'];
    try {
      this.hrvProgressText = '读数据';
      const result = await VPBleSDK.getInstance().healthService
        .getHealthData(this.dayToHealthQuery(this.hrvDay), 1, (p: number) => {
          this.hrvProgressText = `读数据 ${Math.round(p * 100)}%`;
        });
      const data = result.data;
      const rr: number[] = [];
      if (result.success && data) {
        for (const slot of data.fiveMinuteData) {
          for (const v of slot.hrvs) {
            if (v > 0) {
              rr.push(v);
            }
          }
        }
      }
      const lines: string[] = [`【${dayLabels[this.hrvDay]}】RR=${rr.length}`];
      if (rr.length === 0) {
        lines.push('无 RR 数据（未授权时日常数据已剥离 RR；或该天确无测量）');
        this.hrvDayBlocks = [lines.join('\n')];
        this.hrvMsg = '全天 RR=0：若设备确有 HRV 数据，即日常数据出口门控生效的直接证据。';
        return;
      }
      this.hrvProgressText = '计算中';
      const results = await this.computeHrvInWorker(rr, this.hrvRing);
      const scatter = results.scatter;
      const star = results.star;
      const sim = results.similarity;
      const isRing = this.hrvRing;
      const minScatter = isRing ? 300 : 2000;
      const minStarSim = isRing ? 300 : 1500;
      const scatterNote = scatter.result.length > 0
        ? `点数=${scatter.result.length}`
        : `点数=0${rr.length < minScatter ? `（RR不足${minScatter}）` : ''}`;
      lines.push(`散点: control=${scatter.control} ${scatterNote}`);
      const stars: string[] = [];
      for (const s of star.result) {
        stars.push(`type${s.type}=${s.starIndex}星`);
      }
      const starNote = stars.length > 0 ? ` ${stars.join(' ')}`
        : `（RR不足${minStarSim}未计算）`;
      lines.push(`星级: control=${star.control}${starNote}`);
      const proStr = sim.result.lorentzPro.map((p: number) => p.toFixed(1)).join(',');
      lines.push(`相似度: control=${sim.control} 类别=[${sim.result.lorentzIndex.join(',')}] 概率=[${proStr}]`);
      this.hrvDayBlocks = [lines.join('\n')];
      this.hrvMsg = 'HRV 双出口门控：日常数据出口未授权时 RR 已被剥离（RR=0 即门控生效）；' +
        '有 RR 时散点 control=0 同样是门控（分析器出口）。RR>0 但散点 control=1 且点数=0 是数据不足，与门控无关。' +
        '星级/相似度不受门控（对照）。';
    } catch (err) {
      this.hrvMsg = `错误: ${(err as Error).message}`;
    } finally {
      this.hrvQuerying = false;
      this.hrvProgressText = '';
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('门控验证').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          // 授权态提示
          Column() {
            Text('当前设备授权态').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
              .width('100%').margin({ bottom: 6 })
            Text('连接成功后，SDK 会自动向授权服务器登记设备信息，\n运行日志中输出当前设备各功能的授权结果，读取前先确认。')
              .fontSize(12).fontColor('#999999').width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(Color.White).borderRadius(8)
          .margin({ left: 16, right: 16, top: 12 })

          // ① 血氧附加字段
          Column() {
            Text('① 血氧附加字段（日常数据门控）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
              .width('100%').margin({ bottom: 10 })
            Row() {
              this.Spo2DayTab(0, '今天')
              this.Spo2DayTab(1, '昨天')
              this.Spo2DayTab(2, '前天')
              Text(this.spo2Querying ? '读取中' : '读取')
                .fontSize(14).fontColor(Color.White).backgroundColor('#007DFF')
                .borderRadius(6).height(34).padding({ left: 16, right: 16 })
                .margin({ left: 8 })
                .opacity(this.spo2Querying ? 0.5 : 1)
                .onClick(() => this.queryAllDaySpo2())
            }.width('100%')

            if (this.spo2ExtraNonZero >= 0) {
              Text(`5 分钟片 ${this.spo2Count} 个；附加字段非零 ${this.spo2ExtraNonZero} 个`)
                .fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.spo2ExtraNonZero > 0 ? '#34C759' : '#FF9500')
                .margin({ top: 10 }).width('100%')
              ForEach(this.spo2RawLines, (line: string) => {
                Text(line).fontSize(11).fontColor('#666666').margin({ top: 4 }).width('100%')
              }, (line: string, i: number) => `${i}_${line}`)
            }
            if (this.spo2Msg !== '') {
              Text(this.spo2Msg).fontSize(12).fontColor('#999999').margin({ top: 8 }).width('100%')
            }
            Text('未授权判定：spO2 值有而呼吸暂停/缺氧/负荷/校正数组全空，\n且运行日志出现「日常数据血氧附加字段未获服务器授权，已剥离」')
              .fontSize(11).fontColor('#BBBBBB').margin({ top: 8 }).width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor(Color.White).borderRadius(8)
          .margin({ left: 16, right: 16, top: 12 })

          // ② HRV 散点
          Column() {
            Text('② HRV 洛伦兹（散点门控）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
              .width('100%').margin({ bottom: 10 })
            Row() {
              Text('指环设备').fontSize(13).fontColor('#666666').margin({ right: 4 })
              Toggle({ type: ToggleType.Switch, isOn: this.hrvRing })
                .onChange((isOn: boolean) => {
                  this.hrvRing = isOn;
                })
            }.width('100%')
            Row() {
              this.HrvDayTab(0, '今天')
              this.HrvDayTab(1, '昨天')
              this.HrvDayTab(2, '前天')
              Text(this.hrvQuerying ? `读取中 ${this.hrvProgressText}` : '读取')
                .fontSize(14).fontColor(Color.White).backgroundColor('#007DFF')
                .borderRadius(6).height(34).padding({ left: 16, right: 16 })
                .margin({ left: 8 })
                .opacity(this.hrvQuerying ? 0.5 : 1)
                .onClick(() => this.queryHrvScatter())
            }.width('100%')

            if (this.hrvDayBlocks.length > 0) {
              ForEach(this.hrvDayBlocks, (block: string) => {
                Text(block)
                  .fontSize(12).fontColor('#333333').lineHeight(18)
                  .backgroundColor('#F5F7FA').borderRadius(6)
                  .padding(8).margin({ top: 8 }).width('100%')
              }, (block: string, i: number) => `${i}_${block.substring(0, 20)}`)
            }
            if (this.hrvMsg !== '') {
              Text(this.hrvMsg).fontSize(12).fontColor('#999999').margin({ top: 8 }).width('100%')
            }
          }
          .width('100%').padding(16)
          .backgroundColor(Color.White).borderRadius(8)
          .margin({ left: 16, right: 16, top: 12 })

          // ③ ECG 诊断
          Column() {
            Text('③ ECG 诊断结果').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
              .width('100%').margin({ bottom: 6 })
            Text('在「ECG心电」页跑一次完整测量：未授权时波形/进度全程正常，' +
              '但收尾不出现「诊断完成」日志，且运行日志出现「ECG诊断结果未获服务器授权，不下发」；' +
              '历史 ECG 数据读取不受门控。')
              .fontSize(12).fontColor('#999999').width('100%')
            Text('前往 ECG心电 页 →')
              .fontSize(13).fontColor('#007DFF').margin({ top: 10 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/subPages/EcgPage' });
              })
          }
          .width('100%').padding(16)
          .backgroundColor(Color.White).borderRadius(8)
          .margin({ left: 16, right: 16, top: 12, bottom: 24 })
        }.width('100%')
      }
      .width('100%').layoutWeight(1).align(Alignment.Top)
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  Spo2DayTab(day: number, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.spo2Day === day ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.spo2Day === day ? Color.White : '#666666')
      .backgroundColor(this.spo2Day === day ? '#007DFF' : '#ECECEC')
      .borderRadius(6)
      .height(34)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .opacity(this.spo2Querying ? 0.5 : 1)
      .onClick(() => {
        this.spo2Day = day;
      })
  }

  @Builder
  HrvDayTab(day: number, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.hrvDay === day ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.hrvDay === day ? Color.White : '#666666')
      .backgroundColor(this.hrvDay === day ? '#007DFF' : '#ECECEC')
      .borderRadius(6)
      .height(34)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .opacity(this.hrvQuerying ? 0.5 : 1)
      .onClick(() => {
        this.hrvDay = day;
      })
  }
}

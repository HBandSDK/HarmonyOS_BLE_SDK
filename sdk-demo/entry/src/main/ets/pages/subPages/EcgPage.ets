import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  EcgPushEvent,
  EcgPushEventKind,
  EcgInstruction,
  EcgSecondMeasurement,
  EcgDiagnosis,
  EcgWaveformData,
} from '@veepoo/vpble-sdk';

interface LogLine {
  time: string;
  msg: string;
}

/** 波形区高度（vp） */
const WAVE_AREA_H: number = 220;
/** 实时滚动：屏宽约走 2 秒波形 */
const SCREEN_SECONDS: number = 2;
/** 每次定时器推进的点数，周期 = (1000/hz)*step ms，即实时速率 */
const DRAW_STEP: number = 4;
/** 最终波形画布最大宽度（vp），超出则整体压缩 */
const FINAL_MAX_W: number = 4000;

@Entry
@Component
struct EcgPage {
  /** 是否测量中（已 startMeasurement 未收到 RESULT/手动停止） */
  @State measuring: boolean = false;
  /** 是否已完成一次测量（收到 RESULT，画布展示全程波形） */
  @State done: boolean = false;
  @State progress: number = 0;
  @State hr: number = 0;
  @State hrv: number = 0;
  /** 采样/波形频率（INSTRUCTION 说明包） */
  @State samplingFreq: number = 0;
  @State waveFreq: number = 0;
  /** 连续未佩戴计数（每秒包 wearStatus===1 累加，>=5 自动停止） */
  @State wearBadCount: number = 0;
  /** 最终（全程）波形画布宽度，0 = 随屏宽 */
  @State finalW: number = 0;
  @State logLines: LogLine[] = [];
  /** 波形区实际尺寸（vp，onAreaChange 捕获） */
  @State areaW: number = 0;
  @State areaH: number = WAVE_AREA_H;

  private _listener: ((event: EcgPushEvent) => void) | null = null;

  // 波形画布（透明，叠在网格画布上）与网格画布（黑底 ECG 纸格）
  private settingsGrid: RenderingContextSettings = new RenderingContextSettings(true);
  private ctxGrid: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settingsGrid);
  private settingsWave: RenderingContextSettings = new RenderingContextSettings(true);
  private ctxWave: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settingsWave);
  private gridReady: boolean = false;

  // ---- 绘制循环状态 ----
  private _drawTimer: number = 0;
  private _pointW: number = 0;
  private _drawIndex: number = 0;
  private _lastX: number | null = null;
  private _lastY: number | null = null;
  /** 待绘制的实时采样点（WAVEFORM 事件流入，定时器按实时速率消费） */
  private _waveBuf: number[] = [];
  /** 已快照的每秒波形（PROGRESS 到达时快照上一秒） */
  private _completedSeconds: number[][] = [];
  /** 当前秒累积中的波形 */
  private _currentSecond: number[] = [];
  /** 最近一次读到的设备保存 ID（离线读取用） */
  private _lastIds: number[] = [];
  /** 100% 后等待 RESULT/OVER/FAILED 的看门狗（防诊断被授权门控拦下时永久卡住） */
  private _watchdog: number = 0;

  aboutToAppear(): void {
    this._listener = (event: EcgPushEvent) => {
      this.handleEcgPush(event);
    };
    VPBleSDK.getInstance().ecgService.onEcgPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().ecgService.offEcgPush(this._listener);
      this._listener = null;
    }
    this.stopWatchdog();
    this.stopDrawLoop();
    if (this.measuring) {
      VPBleSDK.getInstance().ecgService.stopMeasurement();
    }
  }

  // ==================== ECG 推送分发 ====================
  // 事件语义：INSTRUCTION 说明包 → 拿采样率启动绘制循环；
  // WAVEFORM 每秒实时波形（单位 mV）→ 累积；
  // PROGRESS 每秒进度 → 快照上一秒波形 + 刷 HR/HRV/进度 + 佩戴/设备忙防呆；
  // RESULT / OVER / FAILED 测量结束（有诊断 / 无诊断 / 失败）→ 统一收尾。
  private handleEcgPush(event: EcgPushEvent): void {
    // 总闸：仅测量进行中处理推送。测量结束（手动停止/佩戴防呆/设备忙终止）
    // 后设备仍会送尾巴帧，尤其停止命令的应答帧与说明包同构（数据类型字节
    // 同为 0），会被解码成 INSTRUCTION——没有这道闸会重新启动绘制循环，
    // 波形"停不下来"。
    if (!this.measuring) {
      return;
    }
    if (event.kind === EcgPushEventKind.INSTRUCTION) {
      const d = event.data as EcgInstruction;
      this.samplingFreq = d.samplingFreq;
      this.waveFreq = d.waveFreq;
      this.addLog(`说明包：采样率 ${d.samplingFreq}Hz / 波形 ${d.waveFreq}Hz`);
      // 拿到采样率后按实时速率启动波形绘制
      this.startDrawLoop();
    } else if (event.kind === EcgPushEventKind.WAVEFORM) {
      const d = event.data as EcgWaveformData;
      const samples = d.samples;
      this._currentSecond.push(...samples);
      const buf = this._waveBuf;
      buf.push(...samples);
      this._waveBuf = buf;
    } else if (event.kind === EcgPushEventKind.PROGRESS) {
      // 每秒包到达：把上一秒累积的波形快照（每秒包与每秒波形一一配对）
      if (this._currentSecond.length > 0) {
        this._completedSeconds.push(this._currentSecond);
        this._currentSecond = [];
      }
      const d = event.data as EcgSecondMeasurement;
      this.progress = d.progress;
      this.hr = d.hrPerMinute;
      this.hrv = d.hrv;

      // 设备正忙
      if (d.watchStatus === 255) {
        this.addLog('设备正忙（watchStatus=255），测量终止');
        this.abortMeasurement();
        return;
      }
      // 佩戴防呆：连续 5 秒未检测到佩戴自动停止
      if (d.wearStatus === 1) {
        this.wearBadCount++;
        if (this.wearBadCount >= 5) {
          this.addLog('连续 5 秒未检测到佩戴，自动停止');
          this.abortMeasurement();
          return;
        }
      } else {
        this.wearBadCount = 0;
      }

      // 日志每 5 秒记一条，避免刷屏
      if (d.progress % 5 === 0) {
        this.addLog(`进度 ${d.progress}% HR=${d.hrPerMinute} HRV=${d.hrv}`);
      }
      if (d.progress >= 100) {
        this.addLog('采样完成，等待诊断/结束包...');
        // 看门狗：100% 后 15 秒仍未收到结束事件则主动结束
        //（覆盖设备仅发结束包但帧丢失等异常）
        if (this.measuring && this._watchdog === 0) {
          this.startWatchdog();
        }
      }
    } else if (event.kind === EcgPushEventKind.RESULT) {
      const d = event.data as EcgDiagnosis;
      this.addLog(`诊断完成：HR=${d.heartRate} RR=${d.respiratoryRate} QTc=${d.qtc} ` +
        `SDNN=${d.sdnn}ms RMSSD=${d.rmssd}ms 导联=${d.leadType}`);
      this.finishMeasurement(true);
    } else if (event.kind === EcgPushEventKind.OVER) {
      // 设备已结束测量，本次无诊断报告
      this.addLog('设备已结束测量（无诊断报告）');
      this.finishMeasurement(true);
    } else if (event.kind === EcgPushEventKind.FAILED) {
      // 设备上报测量失败
      this.addLog('设备上报测量失败');
      this.finishMeasurement(false);
    }
  }

  // ==================== 测量控制 ====================

  private async toggle(): Promise<void> {
    if (this.measuring) {
      this.abortMeasurement();
      this.addLog('已手动停止');
    } else {
      this.resetMeasurement();
      this.logLines = [];
      // 先置位再启动：说明包推送可能在 startMeasurement 的 Promise 解决前到达
      this.measuring = true;
      const r = await VPBleSDK.getInstance().ecgService.startMeasurement();
      if (r.success) {
        this.addLog('开始测量，等待说明包...');
      } else {
        this.measuring = false;
        this.addLog(`启动失败：${r.errorMessage ?? '未知'}`);
      }
    }
  }

  /** 中途终止：下发停止命令 + 停止本地绘制（保留已画波形） */
  private abortMeasurement(): void {
    this.stopWatchdog();
    if (this.measuring) {
      VPBleSDK.getInstance().ecgService.stopMeasurement();
    }
    this.measuring = false;
    this.stopDrawLoop();
  }

  /**
   * 测量收尾（RESULT/OVER/FAILED/看门狗超时共用）。
   * 结束约定：收到结束事件后须主动调 stopMeasurement() 结束本次测量
   * （进度到 100% 不代表设备侧已收尾），随后停止本地绘制并按需回放全程波形。
   */
  private finishMeasurement(drawWave: boolean): void {
    this.stopWatchdog();
    this.stopDrawLoop();
    if (this.measuring) {
      VPBleSDK.getInstance().ecgService.stopMeasurement();
    }
    this.measuring = false;
    this.done = true;
    // 收尾：把最后一秒未快照的波形并入
    if (this._currentSecond.length > 0) {
      this._completedSeconds.push(this._currentSecond);
      this._currentSecond = [];
    }
    if (drawWave) {
      this.drawFinalWaveform();
    }
  }

  /** 100% 后的收尾看门狗 */
  private startWatchdog(): void {
    this.stopWatchdog();
    this._watchdog = setTimeout(() => {
      this._watchdog = 0;
      if (this.measuring) {
        this.addLog('等待诊断/结束包超时，主动结束测量');
        this.finishMeasurement(true);
      }
    }, 15000);
  }

  private stopWatchdog(): void {
    if (this._watchdog) {
      clearTimeout(this._watchdog);
      this._watchdog = 0;
    }
  }

  private resetMeasurement(): void {
    this.stopWatchdog();
    this.stopDrawLoop();
    this._waveBuf = [];
    this._completedSeconds = [];
    this._currentSecond = [];
    this._drawIndex = 0;
    this._lastX = null;
    this._lastY = null;
    this.progress = 0;
    this.hr = 0;
    this.hrv = 0;
    this.samplingFreq = 0;
    this.waveFreq = 0;
    this.wearBadCount = 0;
    this.done = false;
    this.finalW = 0;
    // 等画布宽度回落（宽画布 → 100%）后再清
    setTimeout(() => {
      this.ctxWave.clearRect(0, 0, FINAL_MAX_W + this.areaW, this.areaH);
    }, 60);
  }

  // ==================== 波形绘制 ====================

  /** ECG 纸网格：黑底 + 暗色小格 + 基线 */
  private drawGrid(): void {
    if (!this.gridReady || this.areaW <= 0) {
      return;
    }
    const ctx = this.ctxGrid;
    const w = this.areaW;
    const h = this.areaH;
    ctx.clearRect(0, 0, w, h);
    const cell = 8;
    ctx.strokeStyle = '#26262A';
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    for (let x = 0; x <= w; x += cell) {
      ctx.moveTo(x, 0);
      ctx.lineTo(x, h);
    }
    for (let y = 0; y <= h; y += cell) {
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
    }
    ctx.stroke();
    ctx.closePath();
    // 基线
    ctx.strokeStyle = '#3A3A3E';
    ctx.beginPath();
    ctx.moveTo(0, this.sampleToY(0));
    ctx.lineTo(w, this.sampleToY(0));
    ctx.stroke();
    ctx.closePath();
  }

  /** mV 采样点 → 画布 y（基线在 70% 高度，1mV ≈ 35% 高度，限幅） */
  private sampleToY(v: number): number {
    if (this.areaH <= 0) {
      return 0;
    }
    const base = this.areaH * 0.7;
    let y = base - v * (this.areaH * 0.35);
    if (y < 2) {
      y = 2;
    }
    if (y > this.areaH - 2) {
      y = this.areaH - 2;
    }
    return y;
  }

  /**
   * 实时波形绘制循环：按 INSTRUCTION 给出的采样率以实时速率消费 _waveBuf。
   * 屏宽 ≈ 2 秒波形，画到末尾回卷清头部；积压超过 2 秒时加速消化。
   */
  private startDrawLoop(): void {
    this.stopDrawLoop();
    const hz = this.samplingFreq > 0 ? this.samplingFreq : 256;
    const totalPoints = hz * SCREEN_SECONDS;
    this._pointW = this.areaW / totalPoints;
    this._drawIndex = 0;
    this._lastX = null;
    this._lastY = null;
    const tickMs = Math.max(8, Math.round((1000 / hz) * DRAW_STEP));
    this._drawTimer = setInterval(() => {
      if (this.areaW <= 0 || this.finalW > 0) {
        return; // 画布未就绪 / 已切全程视图
      }
      // 攒了 2 秒以上积压则加速消化
      let n = DRAW_STEP;
      if (this._waveBuf.length > hz * SCREEN_SECONDS) {
        n = DRAW_STEP + 2;
      }
      // 擦除前方条带（画新点之前，留出空隙）
      const clearX = (this._drawIndex + DRAW_STEP) * this._pointW;
      this.ctxWave.clearRect(clearX, 0, DRAW_STEP * this._pointW + 10, this.areaH);
      const arr: number[] = this._waveBuf.splice(0, n);
      this.ctxWave.strokeStyle = '#E9291B';
      this.ctxWave.lineWidth = 1.5;
      for (let i = 0; i < n; i++) {
        this._drawIndex++;
        if (this._drawIndex >= totalPoints) {
          this.ctxWave.clearRect(0, 0, 12, this.areaH);
          this._drawIndex = 0;
          this._lastX = null;
          this._lastY = null;
          continue;
        }
        const x = this._drawIndex * this._pointW;
        const y = i < arr.length ? this.sampleToY(arr[i]) : this.sampleToY(0);
        if (this._lastX === null || this._lastY === null) {
          this._lastX = x;
          this._lastY = y;
          continue;
        }
        this.ctxWave.beginPath();
        this.ctxWave.moveTo(this._lastX, this._lastY);
        this.ctxWave.lineTo(x, y);
        this.ctxWave.stroke();
        this.ctxWave.closePath();
        this._lastX = x;
        this._lastY = y;
      }
    }, tickMs);
  }

  private stopDrawLoop(): void {
    if (this._drawTimer) {
      clearInterval(this._drawTimer);
      this._drawTimer = 0;
    }
  }

  /** 测量完成：过滤全 0 秒后把全程波形铺到加宽画布（可横向滚动） */
  private drawFinalWaveform(): void {
    const pts: number[] = [];
    for (const sec of this._completedSeconds) {
      if (sec.every(v => v === 0)) {
        continue; // 电极脱落等产生的全 0 秒
      }
      pts.push(...sec);
    }
    if (pts.length < 2) {
      this.addLog('无有效波形数据');
      return;
    }
    // 密度约 2 点/vp（与实时滚动一致），超长则整体压缩到 FINAL_MAX_W
    const perPoint = Math.min(0.5, FINAL_MAX_W / pts.length);
    this.finalW = Math.ceil(Math.max(this.areaW, pts.length * perPoint));
    // 等画布宽度变化落地后再绘制
    setTimeout(() => {
      const ctx = this.ctxWave;
      ctx.clearRect(0, 0, this.finalW + 20, this.areaH);
      ctx.strokeStyle = '#E9291B';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      for (let i = 0; i < pts.length; i++) {
        const x = i * perPoint;
        const y = this.sampleToY(pts[i]);
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
      ctx.closePath();
    }, 120);
  }

  /** 离线波形预览：取前 5 个有效秒铺满固定宽度画布 */
  private drawHistoryPreview(seconds: number[][]): void {
    const flat: number[] = [];
    for (const sec of seconds) {
      if (sec.length === 0 || sec.every(v => v === 0)) {
        continue;
      }
      flat.push(...sec);
      if (flat.length >= this.samplingFreq * 5 && flat.length >= 256 * 5) {
        break;
      }
    }
    if (flat.length < 2 || this.areaW <= 0) {
      this.addLog('离线数据无有效波形');
      return;
    }
    // 回落到固定宽度画布后再绘制
    this.finalW = 0;
    setTimeout(() => {
      const ctx = this.ctxWave;
      ctx.clearRect(0, 0, this.areaW, this.areaH);
      const dx = this.areaW / flat.length;
      ctx.strokeStyle = '#E9291B';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      for (let i = 0; i < flat.length; i++) {
        const x = i * dx;
        const y = this.sampleToY(flat[i]);
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
      ctx.closePath();
    }, 120);
  }

  // ==================== 离线数据 ====================

  private async readSavedId(): Promise<void> {
    const r = await VPBleSDK.getInstance().ecgService.getSavedId();
    if (r.success) {
      this._lastIds = r.ids ?? [];
      const ids = this._lastIds.length > 0 ? this._lastIds.join(', ') : '无';
      this.addLog(`保存 ID：${ids}（report=${r.isReport}）`);
    } else {
      this.addLog(`读取 ID 失败：${r.errorMessage ?? '未知'}`);
    }
  }

  /** 读取最新一条离线测量（多包传输，含全程波形），预览前 5 秒波形 */
  private async readHistory(): Promise<void> {
    if (this.measuring) {
      return;
    }
    if (this._lastIds.length === 0) {
      await this.readSavedId();
    }
    if (this._lastIds.length === 0) {
      this.addLog('设备无离线测量记录');
      return;
    }
    const id = this._lastIds[this._lastIds.length - 1];
    this.addLog(`读取离线测量 id=${id}...`);
    const r = await VPBleSDK.getInstance().ecgService.getHistory(id);
    if (r.success && r.data) {
      const d = r.data;
      this.addLog(`离线数据：${d.dateTime} 共 ${d.totalSecond} 秒`);
      this.addLog(`平均HR=${d.meanHeartRate} 平均RR=${d.meanRespiratoryRate} HRV=${d.averageHRV} ` +
        `SDNN=${d.diseaseSDNN} RMSSD=${d.diseaseRMSSD}`);
      this.addLog(`波形 ${d.waveformArray.length} 秒，预览前 5 秒`);
      this.drawHistoryPreview(d.waveformArray.map(s => s.waveform));
    } else {
      this.addLog(`读取失败：${r.errorMessage ?? '未知'}`);
    }
  }

  /** HRV 显示值：0 或 255（设备无效值占位）显示 -- */
  private displayHrv(v: number): string {
    return v > 0 && v !== 255 ? `${v}` : '--';
  }

  private addLog(msg: string): void {
    const time = new Date().toLocaleTimeString();
    this.logLines.push({ time, msg });
    if (this.logLines.length > 40) {
      this.logLines.shift();
    }
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('ECG 心电').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      // 波形区：底层网格画布 + 上层透明波形画布（完成/离线读取时加宽可横向滚动）
      Stack() {
        Canvas(this.ctxGrid)
          .width('100%').height('100%')
          .onReady(() => {
            this.gridReady = true;
            this.drawGrid();
          })

        Scroll() {
          Canvas(this.ctxWave)
            .width(this.finalW > 0 ? `${this.finalW}vp` : '100%')
            .height('100%')
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%').height('100%')
      }
      .width('100%').height(WAVE_AREA_H)
      .backgroundColor('#000000').borderRadius(8)
      .alignContent(Alignment.Start)
      .margin({ left: 12, right: 12, top: 4 })
      .onAreaChange((_oldV: Area, newV: Area) => {
        if (typeof newV.width === 'number') {
          this.areaW = newV.width;
        }
        if (typeof newV.height === 'number') {
          this.areaH = newV.height;
        }
        this.drawGrid();
      })

      // 测量说明包信息
      Text(this.samplingFreq > 0 ?
        `采样率 ${this.samplingFreq} Hz / 波形频率 ${this.waveFreq} Hz · 屏宽约 ${SCREEN_SECONDS} 秒` : '等待测量说明包...')
        .fontSize(11).fontColor(this.samplingFreq > 0 ? '#666666' : '#AAAAAA')
        .margin({ top: 6, left: 16, right: 16 })

      Row() {
        Column() {
          Text(this.hr > 0 ? `${this.hr}` : '--').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
          Text('HR').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(this.displayHrv(this.hrv)).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#5856D6')
          Text('HRV').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(`${this.progress}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FF9800')
          Text('PROGRESS').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
      }.width('100%').padding({ top: 12, bottom: 8, left: 16, right: 16 })

      if (this.wearBadCount > 0 && this.measuring) {
        Text('未检测到佩戴，请将手指按住电极...').fontSize(12).fontColor('#E84026')
          .margin({ bottom: 4 })
      }

      Row({ space: 8 }) {
        Button(this.measuring ? '停止' : '开始')
          .layoutWeight(1).height(40)
          .backgroundColor(this.measuring ? '#E84026' : '#007DFF').fontColor(Color.White).borderRadius(8)
          .onClick(() => this.toggle())
        Button('读保存ID')
          .layoutWeight(1).height(40)
          .backgroundColor('#8E8E93').fontColor(Color.White).borderRadius(8)
          .enabled(!this.measuring).opacity(this.measuring ? 0.4 : 1)
          .onClick(() => this.readSavedId())
        Button('读离线数据')
          .layoutWeight(1).height(40)
          .backgroundColor('#8E8E93').fontColor(Color.White).borderRadius(8)
          .enabled(!this.measuring).opacity(this.measuring ? 0.4 : 1)
          .onClick(() => this.readHistory())
      }.width('100%').padding({ left: 12, right: 12 }).margin({ bottom: 12 })

      Scroll() {
        Column() {
          ForEach(this.logLines, (line: LogLine, index: number) => {
            Text(`[${line.time}] ${line.msg}`)
              .fontSize(11).fontColor('#666666').fontFamily('monospace')
              .width('100%').padding({ top: 2, bottom: 2 })
          }, (line: LogLine, index: number) => `${index}_${line.time}`)
        }.width('100%')
      }.width('100%').layoutWeight(1).padding(8)
      .backgroundColor(Color.White).borderRadius(8).margin({ left: 12, right: 12, bottom: 12 })
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}

import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  EcgPushEvent,
  EcgPushEventKind,
  EcgInstruction,
  EcgSecondMeasurement,
  EcgDiagnosis,
} from '@veepoo/vpble-sdk';

interface LogLine {
  time: string;
  msg: string;
}

@Entry
@Component
struct EcgPage {
  @State measuring: boolean = false;
  @State progress: number = 0;
  @State hr: number = 0;
  @State hrv: number = 0;
  @State logLines: LogLine[] = [];

  private _listener: ((event: EcgPushEvent) => void) | null = null;

  aboutToAppear(): void {
    this._listener = (event: EcgPushEvent) => {
      if (event.kind === EcgPushEventKind.INSTRUCTION) {
        const d = event.data as EcgInstruction;
        this.addLog(`采样率 ${d.samplingFreq}Hz / 波形 ${d.waveFreq}Hz`);
      } else if (event.kind === EcgPushEventKind.PROGRESS) {
        const d = event.data as EcgSecondMeasurement;
        this.progress = d.progress;
        this.hr = d.hrPerMinute;
        this.hrv = d.hrv;
        this.addLog(`进度 ${d.progress}% HR=${d.hrPerMinute} HRV=${d.hrv}`);
      } else if (event.kind === EcgPushEventKind.RESULT) {
        const d = event.data as EcgDiagnosis;
        this.addLog(`诊断完成：HR=${d.heartRate} QTc=${d.qtc} SDNN=${d.sdnn}ms RMSSD=${d.rmssd}ms`);
      }
    };
    VPBleSDK.getInstance().ecgService.onEcgPush(this._listener!);
  }

  aboutToDisappear(): void {
    if (this._listener) {
      VPBleSDK.getInstance().ecgService.offEcgPush(this._listener);
      this._listener = null;
    }
    if (this.measuring) {
      VPBleSDK.getInstance().ecgService.stopMeasurement();
    }
  }

  private async toggle(): Promise<void> {
    if (this.measuring) {
      const r = await VPBleSDK.getInstance().ecgService.stopMeasurement();
      this.measuring = false;
      this.addLog(`已停止（${r.success ? '成功' : r.errorMessage ?? '失败'}）`);
    } else {
      this.progress = 0;
      this.hr = 0;
      this.hrv = 0;
      this.logLines = [];
      const r = await VPBleSDK.getInstance().ecgService.startMeasurement();
      if (r.success) {
        this.measuring = true;
        this.addLog('开始测量');
      } else {
        this.addLog(`启动失败：${r.errorMessage ?? '未知'}`);
      }
    }
  }

  private async readSavedId(): Promise<void> {
    const r = await VPBleSDK.getInstance().ecgService.getSavedId();
    if (r.success) {
      this.addLog(`保存 ID：${r.id ?? 0}（report=${r.isReport}）`);
    } else {
      this.addLog(`读取 ID 失败：${r.errorMessage ?? '未知'}`);
    }
  }

  private addLog(msg: string): void {
    const time = new Date().toLocaleTimeString();
    this.logLines.push({ time, msg });
    if (this.logLines.length > 30) {
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

      Row() {
        Column() {
          Text(this.hr > 0 ? `${this.hr}` : '--').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
          Text('HR').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(this.hrv > 0 ? `${this.hrv}` : '--').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#5856D6')
          Text('HRV').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(`${this.progress}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FF9800')
          Text('PROGRESS').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
      }.width('100%').padding({ top: 20, bottom: 20, left: 16, right: 16 })

      Row({ space: 12 }) {
        Button(this.measuring ? '停止' : '开始').width('40%').height(40)
          .backgroundColor(this.measuring ? '#E84026' : '#007DFF').fontColor(Color.White).borderRadius(8)
          .onClick(() => this.toggle())
        Button('读保存ID').width('40%').height(40)
          .backgroundColor('#8E8E93').fontColor(Color.White).borderRadius(8)
          .enabled(!this.measuring).opacity(this.measuring ? 0.4 : 1)
          .onClick(() => this.readSavedId())
      }.width('100%').justifyContent(FlexAlign.Center).margin({ bottom: 12 })

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

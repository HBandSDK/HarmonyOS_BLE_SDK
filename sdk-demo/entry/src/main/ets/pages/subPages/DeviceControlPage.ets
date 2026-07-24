import { router } from '@kit.ArkUI';
import { VPBleSDK, ClearDataType } from '@veepoo/vpble-sdk';

interface LogLine {
  time: string;
  msg: string;
}

@Entry
@Component
struct DeviceControlPage {
  @State busy: boolean = false;
  @State productInfo: string = '--';
  @State findOn: boolean = false;
  @State logLines: LogLine[] = [];

  private addLog(msg: string): void {
    const time = new Date().toLocaleTimeString();
    this.logLines.push({ time, msg });
    if (this.logLines.length > 30) {
      this.logLines.shift();
    }
  }

  private wrap(name: string, fn: () => Promise<string>): Promise<void> {
    if (this.busy) return Promise.resolve();
    this.busy = true;
    return fn().then((msg: string) => {
      this.addLog(`${name}：${msg}`);
    }).catch((err: Error) => {
      this.addLog(`${name} 异常：${err.message}`);
    }).finally(() => {
      this.busy = false;
    });
  }

  private syncTime(): Promise<void> {
    return this.wrap('同步时间', async () => {
      const r = await VPBleSDK.getInstance().deviceControlService.syncTimeNow(new Date());
      return r.success ? 'OK' : (r.errorMessage ?? 'FAIL');
    });
  }

  private findDevice(): Promise<void> {
    return this.wrap('查找设备', async () => {
      const r = await VPBleSDK.getInstance().deviceControlService.findDevice(!this.findOn);
      this.findOn = r.success ? !this.findOn : this.findOn;
      return r.success ? (this.findOn ? '已开启' : '已关闭') : (r.errorMessage ?? 'FAIL');
    });
  }

  private readProductInfo(): Promise<void> {
    return this.wrap('产品信息', async () => {
      const r = await VPBleSDK.getInstance().deviceControlService.getProductInfo();
      if (r.success && r.data) {
        const hex = r.data.raw.map((v: number) => v.toString(16).padStart(2, '0').toUpperCase()).join(' ');
        this.productInfo = `${r.data.raw.length}B`;
        return hex;
      }
      this.productInfo = 'FAIL';
      return r.errorMessage ?? 'FAIL';
    });
  }

  private clearStep(): Promise<void> {
    return this.wrap('清空计步', async () => {
      const r = await VPBleSDK.getInstance().deviceControlService.clearData(ClearDataType.STEP);
      return r.success ? 'OK' : (r.errorMessage ?? 'FAIL');
    });
  }

  private clearAll(): Promise<void> {
    return this.wrap('清空全部数据', async () => {
      const r = await VPBleSDK.getInstance().deviceControlService.clearData(ClearDataType.ALL);
      return r.success ? 'OK' : (r.errorMessage ?? 'FAIL');
    });
  }

  private factoryReset(): Promise<void> {
    return this.wrap('恢复出厂', async () => {
      const r = await VPBleSDK.getInstance().deviceControlService.factoryReset();
      return r.success ? 'OK' : (r.errorMessage ?? 'FAIL');
    });
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('设备控制').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Row() {
        Text('产品信息').fontSize(13).fontColor('#999999').layoutWeight(1)
        Text(this.productInfo).fontSize(13).fontColor('#333333')
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Grid() {
        GridItem() { this.Btn('同步时间', '#007DFF', () => this.syncTime()) }
        GridItem() { this.Btn(this.findOn ? '停止查找' : '查找设备', '#FF9800', () => this.findDevice()) }
        GridItem() { this.Btn('产品信息', '#5856D6', () => this.readProductInfo()) }
        GridItem() { this.Btn('清空计步', '#FF3B30', () => this.clearStep()) }
        GridItem() { this.Btn('清空全部', '#E84026', () => this.clearAll()) }
        GridItem() { this.Btn('恢复出厂', '#8B0000', () => this.factoryReset()) }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(8).columnsGap(8)
      .width('100%').padding({ left: 12, right: 12 })
      .height(160)

      Scroll() {
        Column() {
          ForEach(this.logLines, (line: LogLine, index: number) => {
            Text(`[${line.time}] ${line.msg}`)
              .fontSize(11).fontColor('#666666').fontFamily('monospace')
              .width('100%').padding({ top: 2, bottom: 2 })
          }, (line: LogLine, index: number) => `${index}_${line.time}`)
        }.width('100%')
      }.width('100%').layoutWeight(1).padding(8).margin({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor(Color.White).borderRadius(8)
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  Btn(label: string, color: string, fn: () => Promise<void>) {
    Button(label)
      .fontSize(13).fontColor(Color.White).backgroundColor(color).borderRadius(8)
      .width('100%').height(44)
      .enabled(!this.busy).opacity(this.busy ? 0.4 : 1)
      .onClick(() => fn())
  }
}

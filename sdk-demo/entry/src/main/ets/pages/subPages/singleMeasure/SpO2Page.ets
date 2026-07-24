import { router } from '@kit.ArkUI';
import { VPBleSDK } from '@veepoo/vpble-sdk';

@Entry
@Component
struct SpO2Page {
  @State querying: boolean = false;
  @State spo2: number = 0;
  @State autoEnabled: boolean = false;
  @State logMsg: string = '';

  private async measureOnce(): Promise<void> {
    if (this.querying) return;
    this.querying = true;
    this.spo2 = 0;
    this.logMsg = '测量中...';
    const r = await VPBleSDK.getInstance().bloodOxygenService.startMeasurement();
    if (r.success && r.data) {
      this.spo2 = r.data.spO2;
      this.logMsg = `结果：${r.data.spO2}%`;
    } else {
      this.logMsg = `失败：${r.errorMessage ?? '未知'}`;
    }
    this.querying = false;
  }

  private async toggleAuto(): Promise<void> {
    if (this.querying) return;
    this.querying = true;
    const target = !this.autoEnabled;
    const r = await VPBleSDK.getInstance().bloodOxygenService.setAutoConfig({
      control: 1, enabled: target,
      startHour: 0, startMinute: 0, endHour: 23, endMinute: 59,
    });
    if (r.success && r.data) {
      this.autoEnabled = r.data.enabled;
      this.logMsg = `自动测量已${r.data.enabled ? '开启' : '关闭'}（${r.data.startHour}:${r.data.startMinute.toString().padStart(2, '0')} ~ ${r.data.endHour}:${r.data.endMinute.toString().padStart(2, '0')}）`;
    } else {
      this.logMsg = `设置失败：${r.errorMessage ?? '未知'}`;
    }
    this.querying = false;
  }

  private async readAuto(): Promise<void> {
    if (this.querying) return;
    this.querying = true;
    const r = await VPBleSDK.getInstance().bloodOxygenService.getAutoConfig();
    if (r.success && r.data) {
      this.autoEnabled = r.data.enabled;
      this.logMsg = `读取：${r.data.enabled ? '开' : '关'}（${r.data.startHour}:${r.data.startMinute.toString().padStart(2, '0')} ~ ${r.data.endHour}:${r.data.endMinute.toString().padStart(2, '0')}）`;
    } else {
      this.logMsg = `读取失败：${r.errorMessage ?? '未知'}`;
    }
    this.querying = false;
  }

  aboutToAppear(): void {
    this.readAuto();
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('血氧测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        Text(this.spo2 > 0 ? `${this.spo2}` : '--')
          .fontSize(72).fontWeight(FontWeight.Bold).fontColor('#34C759')
        Text('%').fontSize(14).fontColor('#999999')
      }.width('100%').padding({ top: 36, bottom: 32 })

      Column({ space: 12 }) {
        Button('单次测量').width('60%').height(44)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(8)
          .enabled(!this.querying).opacity(this.querying ? 0.4 : 1)
          .onClick(() => this.measureOnce())

        Row({ space: 12 }) {
          Button(this.autoEnabled ? '关闭自动' : '开启自动').width('45%').height(40)
            .backgroundColor(this.autoEnabled ? '#E84026' : '#34C759').fontColor(Color.White).borderRadius(8)
            .enabled(!this.querying).opacity(this.querying ? 0.4 : 1)
            .onClick(() => this.toggleAuto())
          Button('读取配置').width('45%').height(40)
            .backgroundColor('#8E8E93').fontColor(Color.White).borderRadius(8)
            .enabled(!this.querying).opacity(this.querying ? 0.4 : 1)
            .onClick(() => this.readAuto())
        }
      }

      if (this.logMsg) {
        Text(this.logMsg).fontSize(13).fontColor('#666666')
          .margin({ top: 24, left: 24, right: 24 }).textAlign(TextAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}

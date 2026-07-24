import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  HealthReminderType,
  HealthReminderConfig,
  SedentaryReminderConfig,
} from '@veepoo/vpble-sdk';

@Entry
@Component
struct ReminderPage {
  @State isLoading: boolean = false;
  @State isWriting: boolean = false;
  @State progressText: string = '';
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  // 喝水提醒（0xE7）
  @State drinkEnabled: boolean = false;
  @State drinkStart: string = '08:00';
  @State drinkEnd: string = '20:00';
  @State drinkInterval: number = 30;

  // 久坐提醒（0xE1）
  @State sedEnabled: boolean = false;
  @State sedStart: string = '09:00';
  @State sedEnd: string = '18:00';
  @State sedInterval: number = 60;

  aboutToAppear(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private async refresh(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.progressText = '';
    try {
      const hr = await VPBleSDK.getInstance().reminderService.getHealthReminder((progress: number) => {
        this.progressText = `${Math.round(progress)}%`;
      });
      const sed = await VPBleSDK.getInstance().reminderService.getSedentaryReminder();
      if (hr.success && hr.data) {
        this.drinkEnabled = hr.data.enabled;
        this.drinkStart = hr.data.startTime || this.drinkStart;
        this.drinkEnd = hr.data.endTime || this.drinkEnd;
        this.drinkInterval = hr.data.intervalMinutes > 0 ? hr.data.intervalMinutes : this.drinkInterval;
      }
      if (sed.success && sed.data) {
        this.sedEnabled = sed.data.enabled;
        this.sedStart = sed.data.startTime || this.sedStart;
        this.sedEnd = sed.data.endTime || this.sedEnd;
        this.sedInterval = sed.data.intervalMinutes > 0 ? sed.data.intervalMinutes : this.sedInterval;
      }
      if (!hr.success && !sed.success) {
        this.showToastMsg(`读取失败：${hr.errorMessage ?? sed.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isLoading = false;
      this.progressText = '';
    }
  }

  private fmt(h: number, m: number): string {
    return `${h < 10 ? '0' + h : h}:${m < 10 ? '0' + m : m}`;
  }

  private timePick(initial: string, onAccept: (h: number, m: number) => void): void {
    const parts = initial.split(':');
    const h = parts.length > 0 ? (parseInt(parts[0], 10) || 0) : 0;
    const m = parts.length > 1 ? (parseInt(parts[1], 10) || 0) : 0;
    const d = new Date();
    d.setHours(h, m, 0, 0);
    TimePickerDialog.show({
      selected: d,
      onAccept: (value: TimePickerResult) => {
        onAccept(value.hour ?? 0, value.minute ?? 0);
      },
    });
  }

  private changeDrinkInterval(delta: number): void {
    const v = this.drinkInterval + delta;
    if (v < 5 || v > 240) {
      return;
    }
    this.drinkInterval = v;
  }

  private changeSedInterval(delta: number): void {
    const v = this.sedInterval + delta;
    if (v < 5 || v > 180) {
      return;
    }
    this.sedInterval = v;
  }

  private async saveDrink(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const cfg: HealthReminderConfig = {
        type: HealthReminderType.DRINK_WATER,
        startTime: this.drinkStart,
        endTime: this.drinkEnd,
        intervalMinutes: this.drinkInterval,
        enabled: this.drinkEnabled,
      };
      const r = await VPBleSDK.getInstance().reminderService.setHealthReminder(cfg);
      this.showToastMsg(r.success ? '喝水提醒已保存' : `保存失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`保存异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async saveSed(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const cfg: SedentaryReminderConfig = {
        startTime: this.sedStart,
        endTime: this.sedEnd,
        intervalMinutes: this.sedInterval,
        enabled: this.sedEnabled,
      };
      const r = await VPBleSDK.getInstance().reminderService.setSedentaryReminder(cfg);
      this.showToastMsg(r.success ? '久坐提醒已保存' : `保存失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`保存异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private showToastMsg(msg: string): void {
    this.toastMsg = msg;
    this.showToast = true;
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => { this.showToast = false; }, 2500);
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Text('<').fontSize(20).fontColor('#333333')
            .onClick(() => router.back()).padding({ right: 12 })
          Text('提醒设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
          Text(this.isLoading ? (this.progressText ? `读取中 ${this.progressText}` : '读取中') : '刷新')
            .fontSize(14).fontColor(this.isLoading ? '#999999' : '#007DFF')
            .onClick(() => this.refresh())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.DrinkCard()
            this.SedentaryCard()
          }.width('100%').padding({ bottom: 24 })
        }
        .width('100%').layoutWeight(1).align(Alignment.Top)
      }
      .width('100%').height('100%')

      if (this.showToast) {
        Text(this.toastMsg)
          .fontSize(14).fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .backgroundColor('rgba(0,0,0,0.7)').borderRadius(20).zIndex(1000)
      }
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  DrinkCard() {
    Column({ space: 14 }) {
      Row() {
        Text('喝水提醒').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.drinkEnabled })
          .selectedColor('#007DFF')
          .onChange((on: boolean) => { this.drinkEnabled = on; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Column() {
          Text('开始').fontSize(11).fontColor('#999999')
          Text(this.drinkStart).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#007DFF')
            .margin({ top: 2 })
            .onClick(() => this.timePick(this.drinkStart, (h: number, m: number) => {
              this.drinkStart = this.fmt(h, m);
            }))
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        Text('~').fontSize(14).fontColor('#BBBBBB')
        Column() {
          Text('结束').fontSize(11).fontColor('#999999')
          Text(this.drinkEnd).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#007DFF')
            .margin({ top: 2 })
            .onClick(() => this.timePick(this.drinkEnd, (h: number, m: number) => {
              this.drinkEnd = this.fmt(h, m);
            }))
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
      }.width('100%')

      Row() {
        Text('间隔').fontSize(13).fontColor('#666666').margin({ right: 12 })
        Button('-').width(36).height(32).fontSize(16)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(this.drinkInterval > 5 && !this.isWriting)
          .onClick(() => this.changeDrinkInterval(-5))
        Text(`${this.drinkInterval} 分钟`).fontSize(15).fontColor('#333333')
          .margin({ left: 12, right: 12 })
        Button('+').width(36).height(32).fontSize(16)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(this.drinkInterval < 240 && !this.isWriting)
          .onClick(() => this.changeDrinkInterval(5))
      }.width('100%').alignItems(VerticalAlign.Center)

      Button('保存').width('100%').height(40)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(8)
        .enabled(!this.isWriting)
        .onClick(() => this.saveDrink())
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  SedentaryCard() {
    Column({ space: 14 }) {
      Row() {
        Text('久坐提醒').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.sedEnabled })
          .selectedColor('#34C759')
          .onChange((on: boolean) => { this.sedEnabled = on; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Column() {
          Text('开始').fontSize(11).fontColor('#999999')
          Text(this.sedStart).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#34C759')
            .margin({ top: 2 })
            .onClick(() => this.timePick(this.sedStart, (h: number, m: number) => {
              this.sedStart = this.fmt(h, m);
            }))
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        Text('~').fontSize(14).fontColor('#BBBBBB')
        Column() {
          Text('结束').fontSize(11).fontColor('#999999')
          Text(this.sedEnd).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#34C759')
            .margin({ top: 2 })
            .onClick(() => this.timePick(this.sedEnd, (h: number, m: number) => {
              this.sedEnd = this.fmt(h, m);
            }))
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
      }.width('100%')

      Row() {
        Text('间隔').fontSize(13).fontColor('#666666').margin({ right: 12 })
        Button('-').width(36).height(32).fontSize(16)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(this.sedInterval > 5 && !this.isWriting)
          .onClick(() => this.changeSedInterval(-5))
        Text(`${this.sedInterval} 分钟`).fontSize(15).fontColor('#333333')
          .margin({ left: 12, right: 12 })
        Button('+').width(36).height(32).fontSize(16)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(this.sedInterval < 180 && !this.isWriting)
          .onClick(() => this.changeSedInterval(5))
      }.width('100%').alignItems(VerticalAlign.Center)

      Button('保存').width('100%').height(40)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#34C759').fontColor(Color.White).borderRadius(8)
        .enabled(!this.isWriting)
        .onClick(() => this.saveSed())
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }
}

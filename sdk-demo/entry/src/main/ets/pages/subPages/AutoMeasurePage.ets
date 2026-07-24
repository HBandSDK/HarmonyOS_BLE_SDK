import { router } from '@kit.ArkUI';
import { VPBleSDK, AutoMeasureConfig, AutoMeasureFeature, AutoMeasureSetParams } from '@veepoo/vpble-sdk';

interface FeatureRow {
  feature: number;
  label: string;
  enabled: boolean;
  intervalModifiable: boolean;
  timeSlotModifiable: boolean;
  measureInterval: number;
  stepUnit: number;
  startTime: string;
  stopTime: string;
}

function featureLabel(f: number): string {
  switch (f) {
    case AutoMeasureFeature.PULSE_RATE: return '脉率';
    case AutoMeasureFeature.BLOOD_PRESSURE: return '血压';
    case AutoMeasureFeature.BLOOD_SUGAR: return '血糖';
    case AutoMeasureFeature.STRESS: return '压力';
    case AutoMeasureFeature.BLOOD_OXYGEN: return '血氧';
    case AutoMeasureFeature.BODY_TEMPERATURE: return '体温';
    case AutoMeasureFeature.LORENZ: return '洛伦兹散点';
    case AutoMeasureFeature.HRV: return 'HRV';
    case AutoMeasureFeature.BLOOD_COMPONENTS: return '血液成分';
    default: return `功能${f}`;
  }
}

function toRow(c: AutoMeasureConfig): FeatureRow {
  return {
    feature: c.feature,
    label: featureLabel(c.feature),
    enabled: c.enabled,
    intervalModifiable: c.intervalModifiable,
    timeSlotModifiable: c.timeSlotModifiable,
    measureInterval: c.measureInterval,
    stepUnit: c.stepUnit,
    startTime: c.currentTimeSlot.startTime,
    stopTime: c.currentTimeSlot.stopTime,
  };
}

function validTime(s: string): boolean {
  if (!/^\d{1,2}:\d{2}$/.test(s)) {
    return false;
  }
  const parts = s.split(':');
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

@Entry
@Component
struct AutoMeasurePage {
  @State supported: boolean = false;
  @State b3Value: string = '--';
  @State rows: FeatureRow[] = [];
  @State isLoading: boolean = false;
  @State isWriting: boolean = false;
  @State selectedIndex: number = -1;
  @State editInterval: string = '';
  @State editStart: string = '';
  @State editStop: string = '';
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToAppear(): void {
    // 设备是否支持「多功能定时自动测量」由 A7 特性位 b3AutoMeasure 决定：
    //   1 = 走 B3 协议（本页可用，可配置时间段与间隔）
    //   0 = 走 B8 协议（仅开/关，请使用「自动监测」页）
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    const b3 = dev?.featureList?.b3AutoMeasure;
    this.b3Value = b3 === undefined || b3 === null ? '未知' : `${b3}`;
    this.supported = b3 === 1;
    if (this.supported) {
      this.readConfig();
    }
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private async readConfig(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const r = await VPBleSDK.getInstance().autoMeasureService.readConfig();
      if (r.success && r.data) {
        this.rows = r.data.map((c: AutoMeasureConfig) => toRow(c));
        if (this.selectedIndex >= this.rows.length) {
          this.selectedIndex = -1;
        } else if (this.selectedIndex >= 0) {
          this.syncEditFromRow();
        }
      } else {
        this.showToastMsg(`读取失败: ${r.errorMessage ?? '未知错误'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常: ${(err as Error).message}`);
    } finally {
      this.isLoading = false;
    }
  }

  private syncEditFromRow(): void {
    const row = this.rows[this.selectedIndex];
    if (!row) {
      return;
    }
    this.editInterval = `${row.measureInterval}`;
    this.editStart = row.startTime;
    this.editStop = row.stopTime;
  }

  private onSelectRow(index: number): void {
    this.selectedIndex = index;
    this.syncEditFromRow();
  }

  private _replaceRow(index: number, newRow: FeatureRow): void {
    const newRows: FeatureRow[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      newRows.push(i === index ? newRow : this.rows[i]);
    }
    this.rows = newRows;
  }

  private async toggleEnabled(index: number, isOn: boolean): Promise<void> {
    if (this.isWriting) {
      return;
    }
    const row = this.rows[index];
    if (!row) {
      return;
    }
    const prev = row;
    // 乐观更新开关，失败回滚
    this._replaceRow(index, {
      feature: row.feature, label: row.label, enabled: isOn,
      intervalModifiable: row.intervalModifiable, timeSlotModifiable: row.timeSlotModifiable,
      measureInterval: row.measureInterval, stepUnit: row.stepUnit,
      startTime: row.startTime, stopTime: row.stopTime,
    });
    this.isWriting = true;
    try {
      const params: AutoMeasureSetParams = {
        feature: row.feature,
        enabled: isOn,
        measureInterval: row.measureInterval,
        currentTimeSlot: { startTime: row.startTime, stopTime: row.stopTime },
      };
      const r = await VPBleSDK.getInstance().autoMeasureService.setConfig(params);
      if (!r.success) {
        this._replaceRow(index, prev);
        this.showToastMsg(`设置失败: ${r.errorMessage ?? '未知错误'}`);
      }
    } catch (err) {
      this._replaceRow(index, prev);
      this.showToastMsg(`设置异常: ${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async applyEdit(): Promise<void> {
    if (this.selectedIndex < 0 || this.isWriting) {
      return;
    }
    const row = this.rows[this.selectedIndex];
    if (!row) {
      return;
    }
    const interval = parseInt(this.editInterval, 10);
    if (isNaN(interval) || interval < 0) {
      this.showToastMsg('测量间隔需为非负整数');
      return;
    }
    if (!validTime(this.editStart) || !validTime(this.editStop)) {
      this.showToastMsg('时间格式应为 HH:mm');
      return;
    }
    this.isWriting = true;
    try {
      const params: AutoMeasureSetParams = {
        feature: row.feature,
        enabled: row.enabled,
        measureInterval: interval,
        currentTimeSlot: { startTime: this.editStart, stopTime: this.editStop },
      };
      const r = await VPBleSDK.getInstance().autoMeasureService.setConfig(params);
      if (r.success) {
        this.showToastMsg(`${row.label} 已应用`);
        await this.readConfig();
      } else {
        this.showToastMsg(`设置失败: ${r.errorMessage ?? '未知错误'}`);
      }
    } catch (err) {
      this.showToastMsg(`设置异常: ${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private curRow(): FeatureRow | undefined {
    return this.selectedIndex >= 0 ? this.rows[this.selectedIndex] : undefined;
  }

  private curStepUnit(): number {
    return this.curRow()?.stepUnit ?? 0;
  }

  private canEditInterval(): boolean {
    const r = this.curRow();
    return r ? r.intervalModifiable : false;
  }

  private canEditTimeSlot(): boolean {
    const r = this.curRow();
    return r ? r.timeSlotModifiable : false;
  }

  private editHint(): string {
    const r = this.curRow();
    if (!r) {
      return '';
    }
    const parts: string[] = [];
    parts.push(r.intervalModifiable ? '间隔可改' : '间隔只读');
    parts.push(r.timeSlotModifiable ? '时段可改' : '时段只读');
    return parts.join(' · ');
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
          Text('<')
            .fontSize(20)
            .fontColor('#333333')
            .onClick(() => router.back())
            .padding({ right: 12 })
          Text('自动测量(多功能)')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
          if (this.supported) {
            Text(this.isLoading ? '刷新中' : '刷新')
              .fontSize(14)
              .fontColor(this.isLoading ? '#999999' : '#007DFF')
              .onClick(() => this.readConfig())
          }
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        if (!this.supported) {
          this.UnsupportedHint()
        } else {
          List({ space: 0 }) {
            if (this.rows.length === 0) {
              ListItem() {
                Row() {
                  Text(this.isLoading ? '读取中...' : '未读取到任何功能配置')
                    .fontSize(14)
                    .fontColor('#999999')
                }
                .width('100%')
                .height(56)
                .justifyContent(FlexAlign.Center)
              }
            }
            ForEach(this.rows, (row: FeatureRow, index?: number) => {
              ListItem() {
                this.FeatureRowItem(row, index === undefined ? -1 : index)
              }
            }, (row: FeatureRow) => `${row.feature}`)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.White)
          .divider({ strokeWidth: 0.5, color: '#E0E0E0', startMargin: 16, endMargin: 16 })

          if (this.selectedIndex >= 0) {
            this.EditPanel()
          }
        }
      }
      .width('100%')
      .height('100%')

      if (this.showToast) {
        Text(this.toastMsg)
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .backgroundColor('rgba(0,0,0,0.7)')
          .borderRadius(20)
          .zIndex(1000)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  UnsupportedHint() {
    Column() {
      Text('当前设备不支持「多功能定时自动测量」(B3 协议)')
        .fontSize(15)
        .fontColor('#FF9800')
        .textAlign(TextAlign.Center)
      Text(`设备特性 b3AutoMeasure = ${this.b3Value}（需为 1）`)
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 6 })
      Text('该设备走 B8 开关协议，请使用「自动监测」页控制自动测量开关')
        .fontSize(13)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
    .margin({ left: 16, right: 16, top: 16 })
    .backgroundColor(Color.White)
    .borderRadius(8)
  }

  @Builder
  FeatureRowItem(row: FeatureRow, index: number) {
    Column() {
      Row() {
        Column() {
          Text(row.label)
            .fontSize(16)
            .fontColor('#333333')
          Text(`间隔 ${row.measureInterval}×${row.stepUnit}min · ${row.startTime}-${row.stopTime}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: row.enabled })
          .selectedColor('#007DFF')
          .enabled(!this.isWriting)
          .onChange((isOn: boolean) => this.toggleEnabled(index, isOn))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onSelectRow(index))

      if (this.selectedIndex === index) {
        Divider().color('#E0E0E0').strokeWidth(0.5)
      }
    }
    .width('100%')
    .backgroundColor(this.selectedIndex === index ? '#F0F8FF' : Color.Transparent)
  }

  @Builder
  EditPanel() {
    Column() {
      Row() {
        Text('编辑配置')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .layoutWeight(1)
        Text(this.editHint())
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row() {
        Text('测量间隔')
          .fontSize(14)
          .fontColor('#666666')
          .width(72)
        TextInput({ text: this.editInterval })
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .type(InputType.Number)
          .backgroundColor('#F5F5F5')
          .borderRadius(6)
          .enabled(this.canEditInterval())
          .onChange((v: string) => { this.editInterval = v; })
        Text(`× ${this.curStepUnit()}min`)
          .fontSize(12)
          .fontColor('#999999')
          .width(64)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 8 })

      Row() {
        Text('时间段')
          .fontSize(14)
          .fontColor('#666666')
          .width(72)
        TextInput({ text: this.editStart })
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(6)
          .enabled(this.canEditTimeSlot())
          .onChange((v: string) => { this.editStart = v; })
        Text('~')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ left: 6, right: 6 })
        TextInput({ text: this.editStop })
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(6)
          .enabled(this.canEditTimeSlot())
          .onChange((v: string) => { this.editStop = v; })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 12 })

      Button(this.isWriting ? '应用中' : '应用')
        .fontSize(14)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF')
        .fontColor(Color.White)
        .height(40)
        .width('100%')
        .enabled(!this.isWriting)
        .onClick(() => this.applyEdit())
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }
}

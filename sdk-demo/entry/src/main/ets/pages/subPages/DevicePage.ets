import { router } from '@kit.ArkUI';
import { VPBleSDK, BatteryInfo, BatteryPowerMode, VPDevice } from '@veepoo/vpble-sdk';

@Entry
@Component
struct DevicePage {
  @State battery: BatteryInfo | null = null;
  @State device: VPDevice | null = null;
  @State loading: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      const r = await VPBleSDK.getInstance().deviceService.getBatteryInfo();
      if (r.success && r.data) {
        this.battery = r.data;
      } else {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
      this.device = VPBleSDK.getInstance().getConnectedDevice();
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.loading = false;
    }
  }

  private powerModeText(m: number): string {
    switch (m) {
      case BatteryPowerMode.CHARGING: return '充电中';
      case BatteryPowerMode.LOW_VOLTAGE: return '低电压';
      case BatteryPowerMode.FULL: return '已充满';
      default: return '正常';
    }
  }

  private powerModeColor(m: number): string {
    switch (m) {
      case BatteryPowerMode.CHARGING: return '#34C759';
      case BatteryPowerMode.LOW_VOLTAGE: return '#FF3B30';
      case BatteryPowerMode.FULL: return '#34C759';
      default: return '#999999';
    }
  }

  private levelColor(): string {
    const b = this.battery;
    if (!b) {
      return '#999999';
    }
    if (b.lowBattery) {
      return '#FF3B30';
    }
    if (!b.hasPercentage) {
      return '#5856D6';
    }
    if (b.level >= 50) {
      return '#34C759';
    }
    if (b.level >= 20) {
      return '#FF9500';
    }
    return '#FF3B30';
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
          Text('设备信息').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
          Text(this.loading ? '查询中' : '刷新')
            .fontSize(14).fontColor(this.loading ? '#999999' : '#007DFF')
            .onClick(() => this.refresh())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.BatteryCard()
            this.DeviceCard()
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
  BatteryCard() {
    Column() {
      Text('电量').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ bottom: 12 })

      // hero
      Column() {
        Text(this.battery && this.battery.hasPercentage ? `${this.battery.level}%`
          : (this.battery ? `等级 ${this.battery.levelGrade}` : '--'))
          .fontSize(40).fontWeight(FontWeight.Bold).fontColor(this.levelColor())
        if (this.battery && !this.battery.hasPercentage) {
          Text('设备未返回百分比，显示电量等级（0-4）').fontSize(11).fontColor('#999999')
            .margin({ top: 4 })
        }
      }.width('100%').alignItems(HorizontalAlign.Center).margin({ top: 4, bottom: 16 })

      // 状态徽标
      Row() {
        this.Badge(this.powerModeText(this.battery ? this.battery.powerMode : 0),
          this.powerModeColor(this.battery ? this.battery.powerMode : 0))
        if (this.battery && this.battery.lowBattery) {
          this.Badge('低电量', '#FF3B30')
        }
        if (this.battery && this.battery.sleeping) {
          this.Badge('睡眠中', '#5856D6')
        }
      }.width('100%').margin({ bottom: 12 })

      Divider().color('#F0F0F0').margin({ top: 4, bottom: 12 })

      this.MetricRow('电源模式', this.battery ? this.powerModeText(this.battery.powerMode) : '--')
      this.MetricRow('电量百分比', this.battery && this.battery.hasPercentage ? `${this.battery.level} %` : '--')
      this.MetricRow('电量等级', this.battery ? `${this.battery.levelGrade} / 4` : '--')
      this.MetricRow('电池电压', this.battery && this.battery.voltage > 0 ? `${this.battery.voltage} mV` : '--')
      this.MetricRow('BAT 原始值', this.battery && this.battery.bat > 0 ? `0x${this.battery.bat.toString(16).toUpperCase()}` : '--')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  DeviceCard() {
    Column() {
      Text('设备标识').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ bottom: 4 })
      this.MetricRow('设备名称', this.device?.deviceName || '--')
      this.MetricRow('型号', this.device?.modelName || '--')
      this.MetricRow('软件版本', this.device?.softwareVersion || '--')
      this.MetricRow('固件版本', this.device?.firmwareVersion || '--')
      this.MetricRow('硬件版本', this.device?.hardwareVersion || '--')
      this.MetricRow('序列号', this.device?.serialNumber || '--')
      this.MetricRow('制造商', this.device?.manufacturerName || '--')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  @Builder
  Badge(text: string, color: string) {
    Text(text)
      .fontSize(11).fontColor(Color.White)
      .backgroundColor(color).borderRadius(10)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ right: 8 })
  }

  @Builder
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#333333').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
    }.width('100%').height(40)
  }
}

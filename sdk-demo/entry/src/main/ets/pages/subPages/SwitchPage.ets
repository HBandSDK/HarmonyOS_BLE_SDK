import { router } from '@kit.ArkUI';
import { VPBleSDK, DeviceSwitchConfig, SwitchState, ConfigService } from '@veepoo/vpble-sdk';

interface SwitchItemState {
  label: string;
  supported: boolean;
  isOn: boolean;
}

const SWITCH_FIELDS: string[] = [
  'heartRateAutoDetect',
  'bloodPressureAutoDetect',
  'spo2LowNotification',
  'hrvAutoDetect',
  'ppgAutoMeasure',
  'tempAutoMonitor',
  'bloodGlucoseSwitch',
  'metSwitch',
  'pressureSwitch',
  'bloodCompositionSwitch',
  'fallDetection',
];

const LABELS: string[] = [
  '心率自动检测',
  '血压自动检测',
  '血氧过低提醒',
  'HRV自动检测',
  'PPG自动测量(精准睡眠)',
  '体温自动监测',
  '血糖自动检测',
  '梅脱自动监测',
  '压力自动监测',
  '血液成分自动检测',
  '跌倒提醒',
];

function toItem(label: string, value?: number): SwitchItemState {
  const v = value ?? 0;
  return {
    label: label,
    supported: v !== 0,
    isOn: v === SwitchState.ON,
  };
}

function applyConfigToItems(items: SwitchItemState[], config: DeviceSwitchConfig): SwitchItemState[] {
  const newItems: SwitchItemState[] = [];
  for (let i = 0; i < items.length && i < SWITCH_FIELDS.length; i++) {
    const val = ConfigService.getSwitchValue(config, SWITCH_FIELDS[i]);
    newItems.push(toItem(items[i].label, val));
  }
  return newItems;
}

@Entry
@Component
struct SwitchPage {
  @State switchItems: SwitchItemState[] = [];
  @State isWriting: boolean = false;
  private _writing: boolean = false;

  aboutToAppear(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    const c = dev?.switchConfig;
    this.switchItems = LABELS.map((label, i) => {
      const val = c ? ConfigService.getSwitchValue(c, SWITCH_FIELDS[i]) : undefined;
      return toItem(label, val);
    });

    VPBleSDK.getInstance().configService.onSwitchConfigChange((config: DeviceSwitchConfig) => {
      if (this._writing) {
        return;
      }
      this.switchItems = applyConfigToItems(this.switchItems, config);
      if (dev) {
        dev.switchConfig = config;
      }
    });
  }

  aboutToDisappear(): void {
    VPBleSDK.getInstance().configService.offSwitchConfigChange();
  }

  async updateItem(index: number, isOn: boolean): Promise<void> {
    if (this.isWriting) {
      return;
    }
    const previousItems = this.switchItems;
    const newItems: SwitchItemState[] = [];
    for (let i = 0; i < this.switchItems.length; i++) {
      const item = this.switchItems[i];
      if (i === index) {
        newItems.push({ label: item.label, supported: item.supported, isOn: isOn });
      } else {
        newItems.push(item);
      }
    }
    this.switchItems = newItems;

    this._writing = true;
    this.isWriting = true;
    try {
      const result = await VPBleSDK.getInstance().configService.setSingleSwitch(SWITCH_FIELDS[index], isOn);
      if (!result.success) {
        console.error('[VPBleSDK.SwitchPage]', `setSingleSwitch failed: ${result.errorMessage}`);
        this.switchItems = previousItems;
      }
    } catch (err) {
      console.error('[VPBleSDK.SwitchPage]', `setSingleSwitch exception: ${JSON.stringify(err)}`);
      this.switchItems = previousItems;
    } finally {
      this._writing = false;
      this.isWriting = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(20)
          .fontColor('#333333')
          .onClick(() => router.back())
          .padding({ right: 12 })
        Text('自动监测')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      List({ space: 0 }) {
        ForEach(this.switchItems, (item: SwitchItemState, index?: number) => {
          ListItem() {
            Row() {
              Text(item.label)
                .fontSize(16)
                .fontColor(item.supported ? '#333333' : '#999999')
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: item.isOn })
                .selectedColor('#007DFF')
                .enabled(item.supported && !this.isWriting)
                .onChange((isOn: boolean) => {
                  if (index !== undefined) {
                    this.updateItem(index, isOn);
                  }
                })
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .opacity(item.supported ? 1 : 0.4)
          }
        }, (item: SwitchItemState) => `${item.label}_${item.isOn}`)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .divider({ strokeWidth: 0.5, color: '#E0E0E0', startMargin: 16, endMargin: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}

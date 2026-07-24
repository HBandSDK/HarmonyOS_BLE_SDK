import { router } from '@kit.ArkUI';
import { VPBleSDK, DeviceSwitchConfig, ConfigService } from '@veepoo/vpble-sdk';

interface UnitOption {
  value: number;
  label: string;
}

interface UnitItemState {
  field: string;
  label: string;
  supported: boolean;
  valueText: string;
  currentValue: number;
  options: UnitOption[];
}

interface UnitItemSpec {
  label: string;
  field: string;
  opt1: string;
  opt2: string;
}

const UNIT_SPECS: UnitItemSpec[] = [
  { label: '单位制', field: 'unitSystem', opt1: '公制', opt2: '英制' },
  { label: '时间格式', field: 'timeFormat', opt1: '24小时', opt2: '12小时' },
  { label: 'LED级别', field: 'ledLevel', opt1: '普通', opt2: '深肤色' },
  { label: '温度单位', field: 'tempUnit', opt1: '摄氏度', opt2: '华氏度' },
  { label: '血糖单位', field: 'bloodGlucoseUnit', opt1: 'mmol/L', opt2: 'mg/dL' },
  { label: '尿酸单位', field: 'uricAcidUnit', opt1: 'μmol/L', opt2: 'mg/dL' },
  { label: '血脂单位', field: 'bloodLipidUnit', opt1: 'mmol/L', opt2: 'mg/dL' },
  { label: '皮电单位', field: 'skinElectricUnit', opt1: 'μg/dL', opt2: 'nmol/L' },
];

function buildOptions(opt1: string, opt2: string): UnitOption[] {
  const opts: UnitOption[] = [];
  opts.push({ value: 1, label: opt1 });
  opts.push({ value: 2, label: opt2 });
  return opts;
}

function valueToText(options: UnitOption[], value: number): string {
  for (let i = 0; i < options.length; i++) {
    if (options[i].value === value) {
      return options[i].label;
    }
  }
  return '';
}

function toItemFromSpec(spec: UnitItemSpec, value: number | undefined): UnitItemState {
  const v = value ?? 0;
  const options = buildOptions(spec.opt1, spec.opt2);
  return {
    field: spec.field,
    label: spec.label,
    supported: v !== 0,
    valueText: valueToText(options, v),
    currentValue: v,
    options: options,
  };
}

function buildItems(c?: DeviceSwitchConfig): UnitItemState[] {
  const items: UnitItemState[] = [];
  for (let i = 0; i < UNIT_SPECS.length; i++) {
    const spec = UNIT_SPECS[i];
    const val = c ? ConfigService.getSwitchValue(c, spec.field) : undefined;
    items.push(toItemFromSpec(spec, val));
  }
  return items;
}

function applyConfigToItems(items: UnitItemState[], config: DeviceSwitchConfig): UnitItemState[] {
  const newItems: UnitItemState[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const v = ConfigService.getSwitchValue(config, item.field);
    newItems.push({
      field: item.field,
      label: item.label,
      supported: v !== 0,
      valueText: valueToText(item.options, v),
      currentValue: v,
      options: item.options,
    });
  }
  return newItems;
}

@Entry
@Component
struct UnitPage {
  @State unitItems: UnitItemState[] = [];
  @State isSheetShow: boolean = false;
  @State sheetTitle: string = '';
  @State sheetField: string = '';
  @State sheetOptions: UnitOption[] = [];
  @State sheetCurrentValue: number = 0;
  @State isWriting: boolean = false;
  private _writing: boolean = false;

  aboutToAppear(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    if (dev?.switchConfig) {
      this.unitItems = buildItems(dev?.switchConfig);
    }

    VPBleSDK.getInstance().configService.onSwitchConfigChange((config: DeviceSwitchConfig) => {
      if (this._writing) {
        return;
      }
      this.unitItems = applyConfigToItems(this.unitItems, config);
      if (this.sheetField !== '') {
        this.sheetCurrentValue = ConfigService.getSwitchValue(config, this.sheetField);
      }
      if (dev) {
        dev.switchConfig = config;
      }
    });
  }

  aboutToDisappear(): void {
    VPBleSDK.getInstance().configService.offSwitchConfigChange();
  }

  openSheet(item: UnitItemState): void {
    if (this.isWriting || !item.supported) {
      return;
    }
    this.sheetField = item.field;
    this.sheetTitle = item.label;
    this.sheetOptions = item.options;
    this.sheetCurrentValue = item.currentValue;
    this.isSheetShow = true;
  }

  async selectOption(value: number): Promise<void> {
    if (this.isWriting || this.sheetField === '') {
      return;
    }
    const field = this.sheetField;
    this.isSheetShow = false;

    this._writing = true;
    this.isWriting = true;
    try {
      const result = await VPBleSDK.getInstance().configService.setUnitValue(field, value);
      if (result.success) {
        const newItems: UnitItemState[] = [];
        for (let i = 0; i < this.unitItems.length; i++) {
          const item = this.unitItems[i];
          if (item.field === field) {
            newItems.push({
              field: item.field,
              label: item.label,
              supported: true,
              valueText: valueToText(item.options, value),
              currentValue: value,
              options: item.options,
            });
          } else {
            newItems.push(item);
          }
        }
        this.unitItems = newItems;
        this.sheetField = '';
      } else {
        console.error('[VPBleSDK.UnitPage]', `setUnitValue failed: ${result.errorMessage}`);
      }
    } catch (err) {
      console.error('[VPBleSDK.UnitPage]', `setUnitValue exception: ${JSON.stringify(err)}`);
    } finally {
      this._writing = false;
      this.isWriting = false;
    }
  }

  @Builder
  unitSheetBuilder() {
    Column() {
      Row() {
        Text(this.sheetTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
        Text('×')
          .fontSize(22)
          .fontColor('#999999')
          .onClick(() => {
            this.isSheetShow = false;
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color('#E0E0E0')
        .strokeWidth(0.5)

      ForEach(this.sheetOptions, (opt: UnitOption) => {
        Row() {
          Text(opt.label)
            .fontSize(16)
            .fontColor(this.sheetCurrentValue === opt.value ? '#007DFF' : '#333333')
            .layoutWeight(1)
          if (this.sheetCurrentValue === opt.value) {
            Text('✓')
              .fontSize(18)
              .fontColor('#007DFF')
          }
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.selectOption(opt.value);
        })
      }, (opt: UnitOption) => `${opt.value}`)
    }
    .width('100%')
    .backgroundColor(Color.White)
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(20)
          .fontColor('#333333')
          .onClick(() => router.back())
          .padding({ right: 12 })
        Text('单位设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      List({ space: 0 }) {
        ForEach(this.unitItems, (item: UnitItemState) => {
          ListItem() {
            Row() {
              Text(item.label)
                .fontSize(16)
                .fontColor(item.supported ? '#333333' : '#999999')
                .layoutWeight(1)
              Text(item.valueText)
                .fontSize(14)
                .fontColor(item.supported ? '#666666' : '#999999')
                .margin({ right: 8 })
              Text('>')
                .fontSize(14)
                .fontColor(item.supported ? '#999999' : '#CCCCCC')
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .opacity(item.supported ? 1 : 0.4)
            .onClick(() => {
              this.openSheet(item);
            })
          }
        }, (item: UnitItemState) => `unit_${item.field}_${item.currentValue}_${item.valueText}`)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .divider({ strokeWidth: 0.5, color: '#E0E0E0', startMargin: 16, endMargin: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .bindSheet($$this.isSheetShow, this.unitSheetBuilder(), {
      height: 220,
      dragBar: false,
      backgroundColor: '#FFFFFF',
    })
  }
}

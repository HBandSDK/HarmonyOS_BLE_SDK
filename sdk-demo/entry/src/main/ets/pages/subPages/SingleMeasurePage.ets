import { router } from '@kit.ArkUI';
import { VPBleSDK, DeviceFeatureList } from '@veepoo/vpble-sdk';

interface MeasureEntry {
  label: string;
  /** DeviceFeatureList 字段名 */
  key: string;
  page: string;
  /** 心率反向判断：0x00=有，0x01=无 */
  invert?: boolean;
  /** 微体检/梅脱走 0xDE 手动测量，按 type 区分 */
  manualType?: number;
}

// 心率 invert：heartRateFunction 0x00=有(默认)，0x01=无；其余字段 0=不支持，非 0 支持
const MEASURES: MeasureEntry[] = [
  { label: '心率', key: 'heartRateFunction', page: 'pages/subPages/singleMeasure/HrPage', invert: true },
  { label: '血压', key: 'bloodPressure', page: 'pages/subPages/singleMeasure/BpPage' },
  { label: '血氧', key: 'bloodOxygen', page: 'pages/subPages/singleMeasure/SpO2Page' },
  { label: '体温', key: 'bodyTemp', page: 'pages/subPages/singleMeasure/BodyTempPage' },
  { label: '身体成分', key: 'bodyComposition', page: 'pages/subPages/singleMeasure/BodyCompPage' },
  { label: '血液成分', key: 'bloodComposition', page: 'pages/subPages/singleMeasure/BloodComponentsPage' },
  { label: '血糖', key: 'bloodGlucose', page: 'pages/subPages/singleMeasure/BloodSugarPage' },
  { label: '压力', key: 'pressure', page: 'pages/subPages/singleMeasure/StressPage' },
  { label: '皮肤电', key: 'skinElectric', page: 'pages/subPages/singleMeasure/SkinElectricPage' },
  { label: '微体检', key: 'microCheckup', page: 'pages/subPages/singleMeasure/ManualMeasurePage', manualType: 9 },
  { label: 'HRV', key: 'hrv', page: 'pages/subPages/singleMeasure/HrvPage' },
  { label: '梅脱', key: 'metFunction', page: 'pages/subPages/singleMeasure/ManualMeasurePage', manualType: 6 },
];

function featureValue(fl: DeviceFeatureList | null, key: string): number {
  if (!fl) {
    return -1;
  }
  switch (key) {
    case 'heartRateFunction': return fl.heartRateFunction;
    case 'bloodPressure': return fl.bloodPressure;
    case 'bloodOxygen': return fl.bloodOxygen;
    case 'bodyTemp': return fl.bodyTemp;
    case 'bodyComposition': return fl.bodyComposition;
    case 'bloodComposition': return fl.bloodComposition;
    case 'bloodGlucose': return fl.bloodGlucose;
    case 'pressure': return fl.pressure;
    case 'skinElectric': return fl.skinElectric;
    case 'microCheckup': return fl.microCheckup;
    case 'hrv': return fl.hrv;
    case 'metFunction': return fl.metFunction;
    default: return -1;
  }
}

function isSupported(fl: DeviceFeatureList | null, entry: MeasureEntry): boolean {
  const v = featureValue(fl, entry.key);
  if (v < 0) {
    return false;
  }
  return entry.invert ? v !== 1 : v !== 0;
}

@Entry
@Component
struct SingleMeasurePage {
  @State fl: DeviceFeatureList | null = null;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToAppear(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    this.fl = dev?.featureList ?? null;
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private goTo(entry: MeasureEntry): void {
    if (!isSupported(this.fl, entry)) {
      this.showToastMsg(`设备不支持「${entry.label}」测量`);
      return;
    }
    if (entry.manualType !== undefined) {
      router.pushUrl({ url: entry.page, params: { type: entry.manualType, title: entry.label } });
    } else {
      router.pushUrl({ url: entry.page });
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
          Text('<')
            .fontSize(20)
            .fontColor('#333333')
            .onClick(() => router.back())
            .padding({ right: 12 })
          Text('单项测量')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .layoutWeight(1)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        Text('选择测量项目（灰显表示设备不支持）')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .padding({ left: 16, bottom: 8 })

        // 测量项目网格
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignContent: FlexAlign.Start }) {
          ForEach(MEASURES, (entry: MeasureEntry) => {
            this.MeasureCell(entry)
          }, (entry: MeasureEntry) => `${entry.label}_${entry.key}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
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
  MeasureCell(entry: MeasureEntry) {
    Column() {
      Text(entry.label)
        .fontSize(14)
        .fontColor(isSupported(this.fl, entry) ? '#333333' : '#BBBBBB')
    }
    .width('31%')
    .height(56)
    .margin({ right: '2%', bottom: 12 })
    .backgroundColor(isSupported(this.fl, entry) ? Color.White : '#EEEEEE')
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.goTo(entry))
  }
}

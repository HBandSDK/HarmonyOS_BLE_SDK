import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  HealthQueryDay,
  SportData,
  SportDataSlot,
  SportControlCode,
  SportControlRecord,
  SportControlPushEvent,
} from '@veepoo/vpble-sdk';

@Entry
@Component
struct SportPage {
  // 今日运动汇总
  @State steps: number = 0;
  @State distance: number = 0; // 米
  @State calories: number = 0; // 0.1kcal（协议原始值）
  @State loadingSummary: boolean = false;

  // 运动模式支持
  @State sportSupported: boolean = false;
  @State sportModeCount: number = 0;

  // 专项运动控制
  @State motionType: string = '1';
  @State isWriting: boolean = false;
  @State sportStateText: string = '待机';
  @State rt: SportControlRecord | null = null;

  // 历史记录
  @State crcList: number[] = [];
  @State history: SportData | null = null;
  @State readingHistory: boolean = false;

  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  private _controlListener: ((event: SportControlPushEvent) => void) | null = null;

  aboutToAppear(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    const count = dev?.featureList?.sportModeCount ?? 0;
    this.sportModeCount = count;
    this.sportSupported = count > 0;

    this.loadSummary();

    this._controlListener = (event: SportControlPushEvent) => {
      const arr = event.data;
      if (arr && arr.length > 0) {
        this.rt = arr[arr.length - 1];
      }
    };
    VPBleSDK.getInstance().sportService.onControlPush(this._controlListener!);
  }

  aboutToDisappear(): void {
    if (this._controlListener) {
      VPBleSDK.getInstance().sportService.offControlPush(this._controlListener);
      this._controlListener = null;
    }
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private async loadSummary(): Promise<void> {
    this.loadingSummary = true;
    try {
      const r = await VPBleSDK.getInstance().healthService.getStepData(HealthQueryDay.TODAY);
      if (r.success && r.data) {
        this.steps = r.data.steps;
        this.distance = r.data.distance;
        this.calories = r.data.calories;
      } else {
        this.showToastMsg(`汇总读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`汇总异常：${(err as Error).message}`);
    } finally {
      this.loadingSummary = false;
    }
  }

  private codeText(code: SportControlCode): string {
    switch (code) {
      case SportControlCode.START: return '开始';
      case SportControlCode.PAUSE: return '暂停';
      case SportControlCode.RESUME: return '继续';
      case SportControlCode.STOP: return '停止';
      default: return '未知';
    }
  }

  // 运动控制：开始 / 暂停 / 继续 / 停止
  private async control(code: SportControlCode): Promise<void> {
    if (this.isWriting) {
      return;
    }
    const mt = parseInt(this.motionType, 10);
    if (isNaN(mt) || mt < 0) {
      this.showToastMsg('运动类型需为非负整数');
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().sportService.setControl(mt, code);
      if (r.success) {
        this.sportStateText = this.codeText(code) + '中';
        this.showToastMsg(`${this.codeText(code)} 已发送`);
      } else {
        this.showToastMsg(`操作失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`操作异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async readCrc(): Promise<void> {
    try {
      const r = await VPBleSDK.getInstance().sportService.readModeCrc();
      if (r.success && r.data) {
        this.crcList = r.data.crcList;
        this.showToastMsg(`运动模式 CRC 已读取（${r.data.crcList.length} 条）`);
      } else {
        this.showToastMsg(`CRC 失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`CRC 异常：${(err as Error).message}`);
    }
  }

  private async readHistory(slot: SportDataSlot): Promise<void> {
    if (this.readingHistory) {
      return;
    }
    this.readingHistory = true;
    try {
      const r = await VPBleSDK.getInstance().sportService.readData(slot);
      if (r.success && r.data) {
        this.history = r.data;
        this.showToastMsg(`槽位${slot}：${r.data.allRecord} 条记录`);
      } else {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.readingHistory = false;
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
          Text('运动数据').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
          Text(this.loadingSummary ? '刷新中' : '刷新')
            .fontSize(14).fontColor(this.loadingSummary ? '#999999' : '#007DFF')
            .onClick(() => this.loadSummary())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.SummaryCard()
            if (this.sportSupported) {
              this.ControlCard()
              this.HistoryCard()
            } else {
              Text(`设备不支持运动模式功能（sportModeCount=${this.sportModeCount}）`)
                .fontSize(13).fontColor('#FF9800')
                .margin({ left: 16, right: 16, top: 16 })
            }
          }.width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
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
  SummaryCard() {
    Column() {
      Text('今日运动汇总').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ bottom: 10 })
      Row() {
        Column() {
          Text(`${this.steps}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#007DFF')
          Text('步').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(`${(this.distance / 1000).toFixed(2)}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#34C759')
          Text('km').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
        Column() {
          Text(`${(this.calories / 10).toFixed(1)}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FF9500')
          Text('kcal').fontSize(11).fontColor('#999999')
        }.layoutWeight(1)
      }.width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  ControlCard() {
    Column({ space: 10 }) {
      Text('专项运动控制').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      Row() {
        Text('运动类型').fontSize(14).fontColor('#666666').width(72)
        TextInput({ text: this.motionType })
          .layoutWeight(1).height(40).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.motionType = v; })
        Text('数值含义见开发文档').fontSize(11).fontColor('#BBBBBB')
          .width(96).margin({ left: 8 })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('状态').fontSize(14).fontColor('#666666').width(72)
        Text(this.sportStateText).fontSize(14).fontColor('#FF9800').layoutWeight(1)
      }.width('100%')

      // 实时数据
      Row() {
        this.RtCell('心率', this.rt?.heartRate ?? 0, 'bpm')
        this.RtCell('速度', this.rt?.speed ?? 0, '')
        this.RtCell('配速', this.rt?.pace ?? 0, '')
      }.width('100%')
      Row() {
        this.RtCell('距离', this.rt?.motionDistance ?? 0, '')
        this.RtCell('时长', this.rt?.motionTimes ?? 0, 's')
        this.RtCell('卡路里', this.rt?.calorie ?? 0, '')
      }.width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        Button('开始').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#34C759').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.control(SportControlCode.START))
        Blank().width(8)
        Button('暂停').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#FF9500').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.control(SportControlCode.PAUSE))
        Blank().width(8)
        Button('继续').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.control(SportControlCode.RESUME))
        Blank().width(8)
        Button('停止').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#E84026').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.control(SportControlCode.STOP))
      }.width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  RtCell(label: string, value: number, unit: string) {
    Column() {
      Text(label).fontSize(11).fontColor('#999999')
      Text(value > 0 ? (unit ? `${value} ${unit}` : `${value}`) : '--')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333').margin({ top: 2 })
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
  }

  @Builder
  HistoryCard() {
    Column({ space: 10 }) {
      Row() {
        Text('历史运动记录').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
          .layoutWeight(1)
        Button('读CRC').fontSize(12).height(30)
          .backgroundColor('#8E8E93').fontColor(Color.White).borderRadius(6)
          .onClick(() => this.readCrc())
      }.width('100%')

      Row() {
        Text('有效CRC').fontSize(12).fontColor('#666666').layoutWeight(1)
        // GPS 设备最多 5 条、非 GPS 设备最多 3 条；已过滤空槽位
        Text(this.crcList.length > 0
          ? this.crcList.map((c: number): string => `0x${c.toString(16).toUpperCase()}`).join('  ')
          : '--')
          .fontSize(12).fontColor('#333333').layoutWeight(2)
      }.width('100%')

      Row() {
        Button('槽位0').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.readingHistory)
          .onClick(() => this.readHistory(SportDataSlot.CRC0))
        Blank().width(8)
        Button('槽位1').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.readingHistory)
          .onClick(() => this.readHistory(SportDataSlot.CRC1))
        Blank().width(8)
        Button('槽位2').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.readingHistory)
          .onClick(() => this.readHistory(SportDataSlot.CRC2))
      }.width('100%')

      if (this.history) {
        Column({ space: 4 }) {
          this.HistoryRow('起止', `${this.history.startTime} ~ ${this.history.endTime}`)
          this.HistoryRow('运动类型', `${this.history.motionType}`)
          this.HistoryRow('总步数', `${this.history.allStep}`)
          this.HistoryRow('总距离', `${this.history.allDistance}`)
          this.HistoryRow('总卡路里', `${this.history.allCalorie}`)
          this.HistoryRow('记录条数', `${this.history.allRecord}`)
          this.HistoryRow('暂停次数', `${this.history.pauseCount}`)
        }.width('100%').margin({ top: 4 })
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  @Builder
  HistoryRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#999999').width(80)
      Text(value).fontSize(13).fontColor('#333333').layoutWeight(1)
    }.width('100%')
  }
}

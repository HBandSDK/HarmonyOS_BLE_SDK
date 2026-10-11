import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  EWomenStatus,
  EWomenOprateStatus,
  EBabySex,
  WomenSetting,
  WomenTimeData,
  WomenResult,
} from '@veepoo/vpble-sdk';

/**
 * 女性生理周期示例
 *
 * 五种状态：无状态 / 月经 / 备孕 / 怀孕 / 妈咪。不同状态**必填的日期不同**，
 * 缺失时 SDK 会直接抛错（不向设备发无效数据）：
 *   - MENES / PREREADY：必填 menesLasterday（最近一次经期首日）
 *   - PREING          ：必填 confinementDay（预产期）
 *   - MAMAMI          ：必填 babyBirthday + babySex，另需 menesLasterday
 *
 * readWomenState(womenTag) 的 womenTag 是设备侧数据版本标记，传 3 时按新版布局解析；
 * 不确定就用默认 0。
 */
@Entry
@Component
struct WomenPage {
  @State status: EWomenStatus = EWomenStatus.MENES;
  @State menseLength: number = 5;
  @State menesInterval: number = 28;
  @State logMsg: string = '';
  @State readBack: string = '--';

  /** 示例日期：实际接入请用日期选择器让用户选 */
  private lastPeriodDay: WomenTimeData = { year: 2026, month: 9, day: 1 };
  private dueDay: WomenTimeData = { year: 2027, month: 3, day: 1 };
  private babyBirthday: WomenTimeData = { year: 2026, month: 1, day: 15 };

  private statusName(s: EWomenStatus): string {
    switch (s) {
      case EWomenStatus.NONE: return '无状态';
      case EWomenStatus.MENES: return '月经';
      case EWomenStatus.PREREADY: return '备孕';
      case EWomenStatus.PREING: return '怀孕';
      case EWomenStatus.MAMAMI: return '妈咪';
      default: return '未知';
    }
  }

  private opStatusName(s?: EWomenOprateStatus): string {
    switch (s) {
      case EWomenOprateStatus.SETTING_SUCCESS: return '设置成功';
      case EWomenOprateStatus.SETTING_FAIL: return '设置失败';
      case EWomenOprateStatus.READ_SUCCESS: return '读取成功';
      case EWomenOprateStatus.READ_FAIL: return '读取失败';
      default: return '未知';
    }
  }

  private dayText(d?: WomenTimeData): string {
    return d ? `${d.year}-${d.month}-${d.day}` : '--';
  }

  /** 按当前选中状态装配合法的 WomenSetting */
  private buildSetting(): WomenSetting {
    const s: WomenSetting = {
      womenStatus: this.status,
      menseLength: this.menseLength,
      menesInterval: this.menesInterval,
    };
    if (this.status === EWomenStatus.MENES || this.status === EWomenStatus.PREREADY) {
      s.menesLasterday = this.lastPeriodDay;
    } else if (this.status === EWomenStatus.PREING) {
      s.confinementDay = this.dueDay;
    } else if (this.status === EWomenStatus.MAMAMI) {
      s.menesLasterday = this.lastPeriodDay;
      s.babyBirthday = this.babyBirthday;
      s.babySex = EBabySex.WOMEN;
    }
    return s;
  }

  private async doSet(): Promise<void> {
    try {
      const r: WomenResult = await VPBleSDK.getInstance().womenService.setWomenState(this.buildSetting());
      this.logMsg = r.success
        ? `设置返回：${this.opStatusName(r.opStatus)}`
        : `设置失败：${r.errorMessage ?? '未知'}`;
    } catch (err) {
      // 状态与日期不匹配时 SDK 会抛错（例如选了怀孕却没给预产期）
      this.logMsg = `设置异常：${(err as Error).message}`;
    }
  }

  private async doRead(): Promise<void> {
    try {
      const r: WomenResult = await VPBleSDK.getInstance().womenService.readWomenState();
      if (r.success && r.setting) {
        const s: WomenSetting = r.setting;
        this.readBack = `${this.statusName(s.womenStatus)}｜经期 ${s.menseLength} 天｜周期 ${s.menesInterval} 天\n`
          + `上次经期 ${this.dayText(s.menesLasterday)}｜预产期 ${this.dayText(s.confinementDay)}\n`
          + `宝宝生日 ${this.dayText(s.babyBirthday)}｜性别 ${s.babySex === EBabySex.MAN ? '男' : (s.babySex === EBabySex.WOMEN ? '女' : '--')}`;
        this.logMsg = `读取返回：${this.opStatusName(r.opStatus)}`;
      } else {
        this.readBack = '--';
        this.logMsg = `读取失败：${r.errorMessage ?? this.opStatusName(r.opStatus)}`;
      }
    } catch (err) {
      this.logMsg = `读取异常：${(err as Error).message}`;
    }
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('女性生理周期').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Text('状态').fontSize(13).fontColor('#999999')
            .width('100%').padding({ left: 16, top: 12, bottom: 4 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach([EWomenStatus.NONE, EWomenStatus.MENES, EWomenStatus.PREREADY,
              EWomenStatus.PREING, EWomenStatus.MAMAMI],
              (s: EWomenStatus) => {
                Button(this.statusName(s))
                  .fontSize(13)
                  .fontColor(this.status === s ? Color.White : '#333333')
                  .backgroundColor(this.status === s ? '#007DFF' : '#DDDDDD')
                  .borderRadius(8).height(34).width('30%')
                  .margin({ right: '2%', bottom: 8 })
                  .onClick(() => { this.status = s; })
              }, (s: EWomenStatus) => `${s}`)
          }.width('100%').padding({ left: 16, right: 16 })

          this.StepperRow('经期长度（天）', this.menseLength,
            () => { if (this.menseLength > 1) this.menseLength--; },
            () => { if (this.menseLength < 14) this.menseLength++; })
          this.StepperRow('周期长度（天）', this.menesInterval,
            () => { if (this.menesInterval > 15) this.menesInterval--; },
            () => { if (this.menesInterval < 60) this.menesInterval++; })

          this.InfoRow('上次经期首日', this.dayText(this.lastPeriodDay))
          this.InfoRow('预产期（怀孕）', this.dayText(this.dueDay))
          this.InfoRow('宝宝生日（妈咪）', this.dayText(this.babyBirthday))

          Text('设备回读').fontSize(13).fontColor('#999999')
            .width('100%').padding({ left: 16, top: 16, bottom: 4 })
          Text(this.readBack).fontSize(13).fontColor('#333333')
            .width('100%').padding({ left: 16, right: 16, bottom: 12 })
        }.width('100%')
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(Color.White).borderRadius(8)
      .margin({ left: 16, right: 16, top: 12 })

      Row() {
        Button('下发设置')
          .layoutWeight(1).height(44).backgroundColor('#007DFF')
          .fontColor(Color.White).borderRadius(8)
          .onClick(() => this.doSet())
        Blank().width(16)
        Button('读取设备')
          .layoutWeight(1).height(44).backgroundColor('#666666')
          .fontColor(Color.White).borderRadius(8)
          .onClick(() => this.doRead())
      }.width('100%').padding({ left: 16, right: 16 }).margin({ top: 16, bottom: 16 })

      if (this.logMsg) {
        Text(this.logMsg).fontSize(13).fontColor('#666666')
          .margin({ left: 24, right: 24, bottom: 16 }).textAlign(TextAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  StepperRow(label: string, value: number, onMinus: () => void, onPlus: () => void) {
    Row() {
      Text(label).fontSize(14).fontColor('#666666').layoutWeight(1)
      Button('-').fontSize(16).width(32).height(32).borderRadius(6)
        .backgroundColor('#DDDDDD').fontColor('#333333').onClick(onMinus)
      Text(`${value}`).fontSize(14).fontColor('#333333').width(44).textAlign(TextAlign.Center)
      Button('+').fontSize(16).width(32).height(32).borderRadius(6)
        .backgroundColor('#DDDDDD').fontColor('#333333').onClick(onPlus)
    }.width('100%').height(52).padding({ left: 16, right: 16 })
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(14).fontColor('#333333')
    }.width('100%').height(44).padding({ left: 16, right: 16 })
  }
}

import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  FourGServiceParams,
  FourGServiceInfo,
  JH58SwitchState,
  JH58ReadMode,
  JH58PushEvent,
} from '@veepoo/vpble-sdk';

@Entry
@Component
struct SpecialDevicePage {
  @State isWriting: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  // 4G 服务参数
  @State ip: string = '';
  @State port: string = '';
  @State user: string = '';
  @State password: string = '';
  @State svcSwitch: boolean = false;
  @State dataUpload: boolean = false;
  @State uploadInterval: string = '1';
  @State accountStatus: string = '0';
  @State fourGInfo: FourGServiceInfo | null = null;

  // JH58 PPG
  @State jhStateText: string = '未知';
  @State jhMode: JH58ReadMode = JH58ReadMode.MODE_1;
  @State jhTimestamp: string = '0';
  @State jhBusy: boolean = false;
  @State jhProgress: number = 0;
  @State jhPayloadLen: number = 0;
  @State jhHexPreview: string = '';

  private _jhListener: ((event: JH58PushEvent) => void) | null = null;

  aboutToAppear(): void {
    this._jhListener = (event: JH58PushEvent) => {
      this.jhProgress = event.progress;
      if (event.isComplete && event.mergedPayload) {
        this.jhPayloadLen = event.mergedPayload.length;
        this.jhHexPreview = this.toHexPreview(event.mergedPayload, 64);
        this.jhBusy = false;
        this.showToastMsg(`JH58 数据接收完成（${event.mergedPayload.length} 字节）`);
      }
    };
    VPBleSDK.getInstance().specialDeviceService.onJH58Push(this._jhListener!);
    this.read4G();
    this.readJhSwitch();
  }

  aboutToDisappear(): void {
    if (this._jhListener) {
      VPBleSDK.getInstance().specialDeviceService.offJH58Push(this._jhListener);
      this._jhListener = null;
    }
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private toHexPreview(bytes: number[], max: number): string {
    const n = Math.min(max, bytes.length);
    const parts: string[] = [];
    for (let i = 0; i < n; i++) {
      parts.push(bytes[i].toString(16).toUpperCase().padStart(2, '0'));
    }
    return parts.join(' ') + (bytes.length > max ? ' …' : '');
  }

  private clampInt(s: string, def: number): number {
    const n = parseInt(s, 10);
    return isNaN(n) ? def : n;
  }

  private jhStateLabel(state?: number): string {
    switch (state) {
      case JH58SwitchState.OFF: return '关闭';
      case JH58SwitchState.MODE_1: return '模式 1';
      case JH58SwitchState.MODE_2: return '模式 2';
      default: return '未知';
    }
  }

  // ==================== 4G ====================

  private async read4G(): Promise<void> {
    try {
      const r = await VPBleSDK.getInstance().specialDeviceService.read4GService();
      if (r.success && r.data) {
        this.fourGInfo = r.data;
      } else if (!r.success) {
        this.showToastMsg(`4G 读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`4G 读取异常：${(err as Error).message}`);
    }
  }

  private async save4G(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const params: FourGServiceParams = {
        ipAddress: this.ip,
        port: this.clampInt(this.port, 0),
        userName: this.user,
        password: this.password,
        switch: this.svcSwitch ? 1 : 0,
        dataUploadSwitch: this.dataUpload ? 1 : 0,
        uploadInterval: this.clampInt(this.uploadInterval, 1),
        accountStatus: this.clampInt(this.accountStatus, 0),
      };
      const r = await VPBleSDK.getInstance().specialDeviceService.setup4GService(params);
      this.showToastMsg(r.success ? '4G 服务已保存' : `保存失败：${r.errorMessage ?? '未知'}`);
      await this.read4G();
    } catch (err) {
      this.showToastMsg(`保存异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async approve4G(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().specialDeviceService.approve4GService();
      this.showToastMsg(r.success ? '已发送审批回执' : `审批失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`审批异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  // ==================== JH58 ====================

  private async readJhSwitch(): Promise<void> {
    try {
      const r = await VPBleSDK.getInstance().specialDeviceService.readJH58Switch();
      if (r.success) {
        this.jhStateText = this.jhStateLabel(r.state);
      }
    } catch (_err) {
      // 开关读取失败忽略
    }
  }

  private async setJhSwitch(state: JH58SwitchState): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().specialDeviceService.setJH58Switch(state);
      if (r.success) {
        this.jhStateText = this.jhStateLabel(state);
        this.showToastMsg(`JH58 已${this.jhStateLabel(state)}`);
      } else {
        this.showToastMsg(`设置失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`设置异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async readJhData(): Promise<void> {
    if (this.jhBusy) {
      return;
    }
    this.jhBusy = true;
    this.jhProgress = 0;
    this.jhPayloadLen = 0;
    this.jhHexPreview = '';
    try {
      const r = await VPBleSDK.getInstance().specialDeviceService
        .readJH58RawData(this.jhMode, this.clampInt(this.jhTimestamp, 0));
      if (!r.success) {
        this.jhBusy = false;
        this.showToastMsg(`请求失败：${r.errorMessage ?? '未知'}`);
      } else {
        this.showToastMsg(`已请求 JH58 ${this.jhMode === JH58ReadMode.MODE_1 ? '模式 1' : '模式 2'} 数据，等待推送...`);
      }
    } catch (err) {
      this.jhBusy = false;
      this.showToastMsg(`请求异常：${(err as Error).message}`);
    }
  }

  private async jhContinue(): Promise<void> {
    try {
      await VPBleSDK.getInstance().specialDeviceService.continueJH58Data();
    } catch (err) {
      this.showToastMsg(`继续异常：${(err as Error).message}`);
    }
  }

  private async jhStop(): Promise<void> {
    try {
      await VPBleSDK.getInstance().specialDeviceService.stopJH58Data();
      this.jhBusy = false;
      this.showToastMsg('已停止 JH58 数据流');
    } catch (err) {
      this.showToastMsg(`停止异常：${(err as Error).message}`);
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
          Text('特殊设备').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.FourGCard()
            this.Jh58Card()
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
  FourGCard() {
    Column({ space: 10 }) {
      Text('4G 服务（0xBB）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').width('100%')

      Row() {
        Text('IP 地址').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.ip }).width(140).height(36).type(InputType.Normal)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.ip = v; })
      }.width('100%').alignItems(VerticalAlign.Center)
      Row() {
        Text('端口').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.port }).width(140).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.port = v; })
      }.width('100%').alignItems(VerticalAlign.Center)
      Row() {
        Text('用户名').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.user }).width(140).height(36).type(InputType.Normal)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.user = v; })
      }.width('100%').alignItems(VerticalAlign.Center)
      Row() {
        Text('密码').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.password }).width(140).height(36).type(InputType.Normal)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.password = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('服务开关').fontSize(13).fontColor('#666666').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.svcSwitch }).selectedColor('#007DFF')
          .onChange((on: boolean) => { this.svcSwitch = on; })
      }.width('100%')
      Row() {
        Text('数据上传').fontSize(13).fontColor('#666666').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.dataUpload }).selectedColor('#34C759')
          .onChange((on: boolean) => { this.dataUpload = on; })
      }.width('100%')

      Row() {
        Text('上传间隔(分)').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.uploadInterval }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.uploadInterval = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Button('读取').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#34C759').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.read4G())
        Blank().width(8)
        Button('保存').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.save4G())
        Blank().width(8)
        Button('审批').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#FF9500').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.approve4G())
      }.width('100%').margin({ top: 4 })

      if (this.fourGInfo) {
        Divider().color('#F0F0F0').margin({ top: 4, bottom: 4 })
        this.MetricRow('IP', this.fourGInfo.ipAddress ?? '--')
        this.MetricRow('端口', this.fourGInfo.port !== undefined ? `${this.fourGInfo.port}` : '--')
        this.MetricRow('用户名', this.fourGInfo.userName ?? '--')
        this.MetricRow('服务开关', this.fourGInfo.switch !== undefined ? `${this.fourGInfo.switch}` : '--')
        this.MetricRow('数据上传', this.fourGInfo.dataUploadSwitch !== undefined ? `${this.fourGInfo.dataUploadSwitch}` : '--')
        this.MetricRow('上传间隔', this.fourGInfo.uploadInterval !== undefined ? `${this.fourGInfo.uploadInterval}` : '--')
        this.MetricRow('账户状态', this.fourGInfo.accountStatus !== undefined ? `${this.fourGInfo.accountStatus}` : '--')
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  Jh58Card() {
    Column({ space: 10 }) {
      Text('JH58 PPG 原始数据（0xEB）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      // 测试模式开关
      Row() {
        Text('当前模式').fontSize(13).fontColor('#666666').layoutWeight(1)
        Text(this.jhStateText).fontSize(13).fontColor('#007DFF')
      }.width('100%')
      Row() {
        Button('关闭').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.setJhSwitch(JH58SwitchState.OFF))
        Blank().width(8)
        Button('模式 1').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.setJhSwitch(JH58SwitchState.MODE_1))
        Blank().width(8)
        Button('模式 2').fontSize(12).height(32).layoutWeight(1)
          .backgroundColor('#5856D6').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.setJhSwitch(JH58SwitchState.MODE_2))
      }.width('100%')

      Divider().color('#F0F0F0').margin({ top: 4, bottom: 4 })

      // 数据读取
      Row() {
        Text('读取模式').fontSize(13).fontColor('#666666').layoutWeight(1)
        this.JhModeTab(JH58ReadMode.MODE_1, '模式 1')
        this.JhModeTab(JH58ReadMode.MODE_2, '模式 2')
      }.width('100%').alignItems(VerticalAlign.Center)
      Row() {
        Text('时间戳').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.jhTimestamp }).width(120).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.jhTimestamp = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Button('读取数据').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.jhBusy ? '#CCCCCC' : '#34C759').fontColor(Color.White).borderRadius(6)
          .enabled(!this.jhBusy)
          .onClick(() => this.readJhData())
        Blank().width(8)
        Button('继续').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(this.jhBusy)
          .onClick(() => this.jhContinue())
        Blank().width(8)
        Button('停止').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#E84026').fontColor(Color.White).borderRadius(6)
          .enabled(this.jhBusy)
          .onClick(() => this.jhStop())
      }.width('100%')

      // 进度与结果
      if (this.jhBusy || this.jhProgress > 0) {
        Column({ space: 6 }) {
          Progress({ value: this.jhProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.jhProgress >= 100 ? '#34C759' : '#5856D6').backgroundColor('#E5E5E5').borderRadius(2)
          Text(`进度 ${this.jhProgress}%`).fontSize(12).fontColor('#999999')
        }.width('100%').margin({ top: 4 })
      }
      if (this.jhPayloadLen > 0) {
        Column({ space: 4 }) {
          Text(`已接收 ${this.jhPayloadLen} 字节`).fontSize(12).fontColor('#666666')
          Text(this.jhHexPreview).fontSize(11).fontColor('#999999')
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            .backgroundColor('#F7F7F7').borderRadius(4).padding(8).width('100%')
        }.width('100%').margin({ top: 4 })
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  @Builder
  JhModeTab(m: JH58ReadMode, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.jhMode === m ? Color.White : '#666666')
      .backgroundColor(this.jhMode === m ? '#007DFF' : '#F0F0F0')
      .borderRadius(6)
      .height(28)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .margin({ left: 6 })
      .onClick(() => { this.jhMode = m; })
  }

  @Builder
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#333333').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '58%' })
    }.width('100%').height(40)
  }
}

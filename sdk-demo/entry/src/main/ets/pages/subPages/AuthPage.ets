import { router } from '@kit.ArkUI';
import { VPBleSDK, AuthResult, AuthResponse, AuthAck } from '@veepoo/vpble-sdk';

@Entry
@Component
struct AuthPage {
  @State password: string = '';
  @State result: AuthResponse | null = null;
  @State isWriting: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private parsePwd(): number {
    if (this.password.length === 0) {
      return -1;
    }
    const n = parseInt(this.password, 10);
    if (isNaN(n) || n < 0 || n > 9999) {
      return -1;
    }
    return n;
  }

  private pad4(n: number): string {
    return n.toString().padStart(4, '0');
  }

  private ackText(ack: AuthAck): string {
    switch (ack) {
      case AuthAck.VERIFY_PASSED: return '核准通过';
      case AuthAck.BOTH_PASSED: return '密码与时间均通过';
      case AuthAck.VERIFY_FAILED: return '核准不通过';
      case AuthAck.SET_SUCCESS: return '设置成功';
      case AuthAck.SET_FAILED: return '设置失败';
      case AuthAck.READ_SUCCESS: return '读取成功';
      case AuthAck.READ_FAILED: return '读取失败';
      default: return `未知(${ack})`;
    }
  }

  private raiseHandText(v: number): string {
    switch (v) {
      case 1: return '开启';
      case 2: return '无此功能';
      default: return '关闭';
    }
  }

  private switchText(v: number): string {
    switch (v) {
      case 1: return '开启';
      case 2: return '关闭';
      default: return '无此功能';
    }
  }

  private async run(op: string, fn: () => Promise<AuthResult>): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await fn();
      this.result = r.data ?? null;
      if (r.success) {
        this.showToastMsg(`${op}成功`);
      } else {
        this.showToastMsg(`${op}失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`${op}异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async doVerify(): Promise<void> {
    const pwd = this.parsePwd();
    if (pwd < 0) {
      this.showToastMsg('请输入 4 位数字密码（0000-9999）');
      return;
    }
    await this.run('核准密码', () => VPBleSDK.getInstance().authService.verifyPassword({ password: pwd }));
  }

  private async doSet(): Promise<void> {
    const pwd = this.parsePwd();
    if (pwd < 0) {
      this.showToastMsg('请输入 4 位数字密码（0000-9999）');
      return;
    }
    await this.run('设置密码', () => VPBleSDK.getInstance().authService.setPassword({ password: pwd }));
  }

  private async doRead(): Promise<void> {
    await this.run('读取密码', () => VPBleSDK.getInstance().authService.readPassword());
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
          Text('授权认证').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.FormCard()
            Text('设备连接时已自动认证，此页用于密码核准 / 设置 / 读取及查看认证应答信息')
              .fontSize(11).fontColor('#BBBBBB')
              .margin({ left: 16, right: 16, top: 10 })
            if (this.result) {
              this.ResultCard()
            }
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
  FormCard() {
    Column({ space: 12 }) {
      Row() {
        Text('密码（0000-9999）').fontSize(13).fontColor('#666666').width(120)
        TextInput({ placeholder: '如 0000', text: this.password })
          .layoutWeight(1).height(40).type(InputType.Number).maxLength(4)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.password = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Button('核准密码').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.doVerify())
        Blank().width(8)
        Button('设置密码').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#FF9500').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.doSet())
      }.width('100%')

      Button('读取密码（无需输入）').width('100%').height(40)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#34C759').fontColor(Color.White).borderRadius(8)
        .enabled(!this.isWriting)
        .onClick(() => this.doRead())
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  ResultCard() {
    Column() {
      Row() {
        Text('认证应答').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        Text(this.ackText(this.result!.ack))
          .fontSize(12).fontColor(Color.White)
          .backgroundColor(this.result!.ack === AuthAck.VERIFY_PASSED
            || this.result!.ack === AuthAck.BOTH_PASSED
            || this.result!.ack === AuthAck.SET_SUCCESS
            || this.result!.ack === AuthAck.READ_SUCCESS ? '#34C759' : '#FF3B30')
          .borderRadius(10).padding({ left: 10, right: 10, top: 4, bottom: 4 })
      }.width('100%').margin({ bottom: 4 })

      this.MetricRow('设备密码', this.pad4(this.result!.password))
      this.MetricRow('型号 ID', `0x${this.result!.deviceId.toString(16).toUpperCase()} (${this.result!.deviceId})`)
      this.MetricRow('固件版本', this.result!.version || '--')
      this.MetricRow('完整版本', this.result!.tVersion || '--')
      this.MetricRow('MAC 地址', this.result!.mac || '--')
      this.MetricRow('DFU 状态', this.result!.dfuStatus === 1 ? 'DFU 中' : '正常')
      this.MetricRow('抬手亮屏', this.raiseHandText(this.result!.raiseHand))
      this.MetricRow('防丢失', this.switchText(this.result!.findPhone))
      this.MetricRow('佩戴检测', this.switchText(this.result!.wearFlag))
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
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

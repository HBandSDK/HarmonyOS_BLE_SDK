import { router } from '@kit.ArkUI';
import { VPBleSDK, BtStatusInfo, BtState } from '@veepoo/vpble-sdk';

const BT_STATE_LABELS: string[] = ['未连接', '已连接', '广播中'];
const CONNECT_TIMEOUT_MS: number = 30000;

@Entry
@Component
struct BtPage {
  @State btState: string = '--';
  @State isConnected: boolean = false;
  @State isConnecting: boolean = false;
  private _connectTimerId: number = -1;

  aboutToAppear(): void {
    this.loadFromDevice();

    VPBleSDK.getInstance().btService.onBtStatusChange((status: BtStatusInfo) => {
      this.applyStatus(status);
    });
  }

  aboutToDisappear(): void {
    VPBleSDK.getInstance().btService.offBtStatusChange();
    this._clearConnectTimer();
  }

  private loadFromDevice(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    if (dev?.btStatus) {
      this.applyStatus(dev.btStatus);
    }
  }

  private applyStatus(status: BtStatusInfo): void {
    console.log("VPBleSDK.", `status.btState = ${status.btState}`)
    this.btState = BT_STATE_LABELS[status.btState] ?? `未知(${status.btState})`;
    this.isConnected = status.btState === BtState.CONNECTED;

    // 连接成功，取消超时监测并恢复按钮
    if (this.isConnected && this.isConnecting) {
      this._clearConnectTimer();
      this.isConnecting = false;
    }
  }

  private _clearConnectTimer(): void {
    if (this._connectTimerId !== -1) {
      clearTimeout(this._connectTimerId);
      this._connectTimerId = -1;
    }
  }

  private async connectTest(): Promise<void> {
    if (this.isConnected || this.isConnecting) {
      return;
    }

    this.isConnecting = true;

    // 启动 30s 超时监测，超时后恢复按钮
    this._connectTimerId = setTimeout(() => {
      console.log('[BtPage]', 'BT 连接超时');
      this._connectTimerId = -1;
      this.isConnecting = false;
    }, CONNECT_TIMEOUT_MS);

    try {
      await VPBleSDK.getInstance().btService.connectBt();
    } catch (err) {
      console.error('[BtPage]', `connectBt exception: ${JSON.stringify(err)}`);
      this._clearConnectTimer();
      this.isConnecting = false;
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('<')
          .fontSize(20)
          .fontColor('#333333')
          .onClick(() => router.back())
          .padding({ right: 12 })
        Text('BT管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      // 状态信息区
      Column() {
        Row() {
          Text('BT状态')
            .fontSize(15)
            .fontColor('#666666')
            .width(90)
          Text(this.btState)
            .fontSize(15)
            .fontColor('#333333')
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ left: 16, right: 16, top: 16 })

      // BT 开关控制区
      Column() {
        Text('BT开关')
          .fontSize(15)
          .fontColor('#666666')
          .width('100%')
          .padding({ left: 16, top: 12, bottom: 8 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          Button(this.isConnecting ? '连接中' : (this.isConnected ? '已连接' : '开启'))
            .fontSize(14)
            .backgroundColor(this.isConnected || this.isConnecting ? '#CCCCCC' : Color.Blue)
            .fontColor(Color.White)
            .height(36)
            .margin({ left: 12, bottom: 12 })
            .enabled(!this.isConnected && !this.isConnecting)
            .onClick(() => this.connectTest())
        }
        .width('100%')
        .padding({ left: 0, right: 16, bottom: 12 })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius(8)
      .margin({ left: 16, right: 16, top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}

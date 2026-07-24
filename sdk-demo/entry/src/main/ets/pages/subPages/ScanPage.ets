import { BleDevice, VPBleSDK } from '@veepoo/vpble-sdk';
import { BleManager } from '../../ble/Index';
import { router } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

@Entry
@Component
struct ScanPage {
  @State deviceList: BleDevice[] = [];
  @State isScanning: boolean = false;
  @State isLoading: boolean = false;
  @State loadingText: string = '';
  @State toastMsg: string = '';
  @State showToast: boolean = false;

  private bleManager: BleManager | null = null;
  private toastTimer: number = -1;

  private static readonly BLE_PERMISSIONS: Permissions[] = [
    'ohos.permission.ACCESS_BLUETOOTH',
    'ohos.permission.APPROXIMATELY_LOCATION',
    'ohos.permission.LOCATION',
  ];

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text('< Back')
            .fontSize(16)
            .fontColor('#007DFF')
            .onClick(() => router.back())
            .padding({ right: 12 })

          Text('Scan Devices')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('  ')
            .fontSize(16)
            .padding({ left: 12 })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)

        // 扫描按钮
        Button(this.isScanning ? 'Stop Scan' : 'Start Scan')
          .width('90%')
          .height(44)
          .fontSize(16)
          .margin({ top: 16, bottom: 16 })
          .enabled(!this.isLoading)
          .onClick(() => this.toggleScan())

        // 设备列表
        if (this.deviceList.length === 0 && !this.isScanning) {
          Column() {
            Text('No devices found')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.deviceList, (device: BleDevice) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(device.deviceName || 'Unknown')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                    Text(device.mac)
                      .fontSize(12)
                      .fontColor('#999999')
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(`${device.rssi} dBm`)
                    .fontSize(12)
                    .fontColor('#666666')
                    .margin({ right: 12 })
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Color.White)
                .borderRadius(8)
                .onClick(() => this.connectDevice(device))
              }
              .margin({ bottom: 6 })
            }, (device: BleDevice) => device.mac)
          }
          .width('92%')
          .layoutWeight(1)
          .margin({ left: '4%', right: '4%' })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')

      // 全屏 Loading
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#007DFF')
          Text(this.loadingText)
            .fontSize(14)
            .fontColor('#333333')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.3)')
        .justifyContent(FlexAlign.Center)
        .zIndex(999)
      }

      // Toast 提示
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
  }

  aboutToAppear(): void {
    this.bleManager = new BleManager((devices: BleDevice[]) => {
      this.deviceList = devices;
    });
    this.toggleScan();
  }

  aboutToDisappear(): void {
    if (this.isScanning && this.bleManager) {
      this.bleManager.stopScan();
      this.isScanning = false;
    }
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private async toggleScan(): Promise<void> {
    if (!this.bleManager) {
      return;
    }
    if (this.isScanning) {
      this.bleManager.stopScan();
      this.isScanning = false;
    } else {
      const granted = await this.requestBlePermissions();
      if (!granted) {
        this.showToastMsg('BLE permissions not granted');
        return;
      }
      this.deviceList = [];
      this.bleManager.startScan();
      this.isScanning = true;
    }
  }

  private connectDevice(device: BleDevice): void {
    // 停止扫描
    if (this.isScanning && this.bleManager) {
      this.bleManager.stopScan();
      this.isScanning = false;
    }

    this.isLoading = true;
    this.loadingText = `Connecting to ${device.deviceName || 'Unknown'}...`;

    VPBleSDK.getInstance().connectDevice(device).then(() => {
      this.isLoading = false;
      this.showToastMsg('Connected successfully');
      // 延迟返回上一页
      setTimeout(() => {
        router.back();
      }, 1000);
    }).catch((err: Error) => {
      this.isLoading = false;
      this.showToastMsg(`Connection failed: ${err.message}`);
    });
  }

  private showToastMsg(msg: string): void {
    this.toastMsg = msg;
    this.showToast = true;
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.showToast = false;
    }, 2500);
  }

  private async requestBlePermissions(): Promise<boolean> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, ScanPage.BLE_PERMISSIONS);
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          return false;
        }
      }
      return true;
    } catch (err) {
      return false;
    }
  }
}

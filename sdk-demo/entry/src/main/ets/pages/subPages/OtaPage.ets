import { router } from '@kit.ArkUI';
import { VPBleSDK, OtaProgress } from '@veepoo/vpble-sdk';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';

@Entry
@Component
struct OtaPage {
  @State fileName: string = '';
  @State fileSize: number = 0;
  @State firmwareData: Uint8Array | null = null;
  @State upgrading: boolean = false;
  @State percent: number = 0;
  @State bytesTransferred: number = 0;
  @State totalBytes: number = 0;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private formatBytes(n: number): string {
    if (n >= 1024 * 1024) {
      return `${(n / (1024 * 1024)).toFixed(2)} MB`;
    }
    if (n >= 1024) {
      return `${(n / 1024).toFixed(1)} KB`;
    }
    return `${n} B`;
  }

  private extractName(uri: string): string {
    const idx = uri.lastIndexOf('/');
    return idx >= 0 ? uri.substring(idx + 1) : uri;
  }

  private async pickFirmware(): Promise<void> {
    if (this.upgrading) {
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await docPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(file.path);
        const buffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buffer);
        this.firmwareData = new Uint8Array(buffer);
        this.fileSize = stat.size;
        this.fileName = this.extractName(uri);
        this.percent = 0;
        this.bytesTransferred = 0;
        this.totalBytes = stat.size;
        this.showToastMsg(`已加载 ${this.fileName}（${this.formatBytes(stat.size)}）`);
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      this.showToastMsg(`读取文件失败：${(err as Error).message}`);
    }
  }

  private async startOta(): Promise<void> {
    if (this.upgrading || !this.firmwareData) {
      return;
    }
    this.upgrading = true;
    this.percent = 0;
    this.bytesTransferred = 0;
    this.totalBytes = this.firmwareData.byteLength;
    try {
      const r = await VPBleSDK.getInstance().otaService.startJlOta(
        this.firmwareData,
        (p: OtaProgress) => {
          this.percent = Math.min(100, Math.round(p.percent));
          this.bytesTransferred = p.bytesTransferred;
          if (p.totalBytes > 0) {
            this.totalBytes = p.totalBytes;
          }
        },
      );
      this.showToastMsg(r.success ? '升级完成' : `升级失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`升级异常：${(err as Error).message}`);
    } finally {
      this.upgrading = false;
    }
  }

  private cancelOta(): void {
    if (!this.upgrading) {
      return;
    }
    VPBleSDK.getInstance().otaService.cancelUpgrade();
    this.showToastMsg('已请求取消');
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
          Text('固件升级').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.FileCard()
            this.UpgradeCard()
            Text('需设备支持 JL RCSP 服务（AE00），并选择与设备匹配的固件文件，否则升级将失败。')
              .fontSize(11).fontColor('#BBBBBB')
              .margin({ left: 16, right: 16, top: 10 })
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
  FileCard() {
    Column({ space: 12 }) {
      Text('固件文件').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').width('100%')
      Row() {
        Column() {
          Text(this.fileName || '未选择文件').fontSize(14)
            .fontColor(this.fileName ? '#333333' : '#BBBBBB').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.fileSize > 0) {
            Text(this.formatBytes(this.fileSize)).fontSize(12).fontColor('#999999').margin({ top: 2 })
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('选择文件').fontSize(13).height(36)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.upgrading)
          .onClick(() => this.pickFirmware())
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  UpgradeCard() {
    Column({ space: 14 }) {
      Text('升级（JL RCSP OTA）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      // 进度
      Column({ space: 6 }) {
        Progress({ value: this.percent, total: 100, type: ProgressType.Linear })
          .width('100%')
          .color(this.percent >= 100 ? '#34C759' : '#007DFF').backgroundColor('#E5E5E5').borderRadius(2)
        Row() {
          Text(`${this.percent}%`).fontSize(13).fontColor('#333333')
          Blank().layoutWeight(1)
          Text(this.totalBytes > 0
            ? `${this.formatBytes(this.bytesTransferred)} / ${this.formatBytes(this.totalBytes)}`
            : '--').fontSize(12).fontColor('#999999')
        }.width('100%')
      }.width('100%')

      Row() {
        Button(this.upgrading ? '升级中...' : '开始升级').fontSize(14).height(40).layoutWeight(1)
          .backgroundColor(this.upgrading ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(8)
          .enabled(!this.upgrading && this.firmwareData !== null)
          .onClick(() => this.startOta())
        Blank().width(10)
        Button('取消').fontSize(14).height(40).layoutWeight(1)
          .backgroundColor('#E84026').fontColor(Color.White).borderRadius(8)
          .enabled(this.upgrading)
          .onClick(() => this.cancelOta())
      }.width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }
}

import { router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { CropModel, CropView } from 'crop_library';

/** 裁剪页路由参数 */
interface CropPageParams {
  srcUri: string;
  ratioW: number;
  ratioH: number;
  isCircle: boolean;
}

/**
 * 照片表盘裁剪页:按目标机型主图比例取景(最大宽 320vp),圆形表盘用椭圆取景框。
 *
 * 确认后输出 PNG 到 cacheDir 并携带 cropFilePath 返回表盘页——用 PNG 而非 JPEG
 * 是为了保留椭圆外的透明区:表盘页转换小图时按「透明铺黑」处理(圆形表盘小图兼容),
 * 不透明图片该处理无效。
 */
@Entry
@Component
struct PhotoCropPage {
  @State model: CropModel = new CropModel();
  @State isCircle: boolean = false;
  @State busy: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;
  private srcUri: string = '';
  private ratioW: number = 1;
  private ratioH: number = 1;
  private angle: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as CropPageParams;
    this.srcUri = params?.srcUri ?? '';
    this.ratioW = params?.ratioW && params.ratioW > 0 ? params.ratioW : 1;
    this.ratioH = params?.ratioH && params.ratioH > 0 ? params.ratioH : 1;
    this.isCircle = params?.isCircle ?? false;
    const frame = this.resizeRect(this.ratioW, this.ratioH);
    this.model.setImage(this.srcUri)
      .setFrameWidth(vp2px(frame.width))
      .setFrameHeight(vp2px(frame.height))
      .setEllipseFrame(this.isCircle)
      .setFrameRatio(1);
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('<').fontSize(20).fontColor('#333333')
            .onClick(() => router.back()).padding({ right: 12 })
          Text('裁剪照片').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        CropView({ model: this.model })
          .layoutWeight(1).width('100%')

        Row() {
          Button('旋转').fontSize(14).height(40).layoutWeight(1)
            .backgroundColor('#666666').fontColor(Color.White).borderRadius(8)
            .onClick(() => {
              this.angle = (this.angle + 90) % 360;
              this.model.rotate(this.angle);
            })
          Blank().width(12)
          Button('重置').fontSize(14).height(40).layoutWeight(1)
            .backgroundColor('#666666').fontColor(Color.White).borderRadius(8)
            .onClick(() => {
              this.angle = 0;
              this.model.reset();
            })
          Blank().width(12)
          Button(this.busy ? '处理中...' : '确认裁剪').fontSize(14).height(40).layoutWeight(2)
            .backgroundColor(this.busy ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(8)
            .enabled(!this.busy && this.srcUri !== '')
            .onClick(() => this.confirmCrop())
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 24 })
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

  /** 取景框等比缩放,最大宽 320vp(对齐宿主参考实现的裁剪页口径) */
  private resizeRect(width: number, height: number): SizeRect {
    if (width <= 320) {
      return { width: width, height: height };
    }
    const scale = 320 / width;
    return { width: 320, height: height * scale };
  }

  /**
   * 圆形表盘:把椭圆外像素 alpha 置 0(输出 PNG 保留透明区)。
   * 表盘页转换小图时对透明区铺黑,即得到圆底小图。
   */
  private applyEllipseAlpha(pm: image.PixelMap): void {
    const info = pm.getImageInfoSync();
    const w = info.size.width;
    const h = info.size.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const buf = new ArrayBuffer(pm.getPixelBytesNumber());
    pm.readPixelsToBufferSync(buf);
    const u8 = new Uint8Array(buf);
    const halfW = w / 2;
    const halfH = h / 2;
    for (let y = 0; y < h; y++) {
      const dy = (y + 0.5 - halfH) / halfH;
      for (let x = 0; x < w; x++) {
        const dx = (x + 0.5 - halfW) / halfW;
        if (dx * dx + dy * dy > 1) {
          u8[(y * w + x) * 4 + 3] = 0;
        }
      }
    }
    pm.writeBufferToPixels(buf);
  }

  private async confirmCrop(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const pm = await this.model.crop();
      if (this.isCircle) {
        this.applyEllipseAlpha(pm);
      }
      const ctx = getContext(this) as common.Context;
      const path = `${ctx.cacheDir}/dial_crop_${Date.now()}.png`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        const packer = image.createImagePacker();
        const opts: image.PackingOption = { format: 'image/png', quality: 100 };
        await packer.packToFile(pm, file.fd, opts);
      } finally {
        fs.closeSync(file);
      }
      router.back({ url: 'pages/subPages/DialPage', params: { cropFilePath: `file://${path}` } });
    } catch (err) {
      this.showToastMsg(`裁剪失败:${(err as Error).message}`);
    } finally {
      this.busy = false;
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
}

interface SizeRect {
  width: number;
  height: number;
}

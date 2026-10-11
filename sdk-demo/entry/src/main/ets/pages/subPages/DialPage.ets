import { router } from '@kit.ArkUI';
import {
  VPBleSDK,
  DialDataType,
  DialInfoResult,
  CustomBgDialParams,
  UIStyleType,
  UIStyleResult,
  UIStyleControl,
  SDKEventType,
  DialTransferState,
  DeviceDialFile,
  NetworkDialItem,
  findPhotoDialSize,
  Logger,
  LogSink,
  LogLevel,
} from '@veepoo/vpble-sdk';
import picker from '@ohos.file.picker';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct DialPage {
  @State isWriting: boolean = false;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  // 表盘信息读取结果
  @State dialResult: DialInfoResult | null = null;

  // 自定义背景参数
  @State bgDefault: boolean = false;
  @State bgTimePos: string = '1';
  @State bgTimeTop: string = '1';
  @State bgTimeBottom: string = '0';
  @State bgR: string = '255';
  @State bgG: string = '255';
  @State bgB: string = '255';

  // UI 风格
  @State uiStyle: string = '0';
  @State uiStyleType: UIStyleType = UIStyleType.FACTORY;
  @State uiResult: UIStyleResult | null = null;
  // 设备端切表盘/UI 风格的主动推送（UI_STYLE_CHANGED）
  @State lastUiPush: string = '--';
  private uiPushHandler = (data: ESObject): void => {
    const r = data as UIStyleResult;
    this.lastUiPush = `style=${r.style ?? '--'} styleType=${r.styleType ?? '--'}`;
  };

  // 市场表盘传输
  @State marketFileName: string = '';
  @State marketFileSize: number = 0;
  // ⚠️ 二进制不可用 @State 持有：ArkUI 状态管理包装 ArrayBuffer 失败后，
  // 任何读取都会抛 TypeError "don't have internal slot"（stateMgmt get）。
  // 表盘二进制用普通字段；UI 只观察 fileName/size/progress/status 等基础类型。
  private marketBin: ArrayBuffer | null = null;
  @State marketTransferring: boolean = false;
  @State marketProgress: number = 0;
  @State marketStatus: string = '';

  // 网络市场表盘列表
  @State netDialItems: NetworkDialItem[] = [];
  @State netDialCounts: number = 0;
  @State netDialPageIndex: number = 0;
  @State netDialLoading: boolean = false;
  @State netDialStatus: string = '';

  // 照片表盘传输
  @State photoUri: string = '';
  @State mainW: string = '240';
  @State mainH: string = '240';
  @State smallW: string = '240';
  @State smallH: string = '240';
  @State photoTransferring: boolean = false;
  @State photoProgress: number = 0;
  @State photoStatus: string = '';
  // 是否圆形表盘(查表得到):裁剪页椭圆取景 + 小图转换铺黑底
  @State photoIsCircle: boolean = false;
  @State photoSizeNote: string = '';
  // 中科照片表盘:569 系列开关(影响通道编码参数)
  @State isZK569x: boolean = false;
  /** 选图后待裁剪的临时 URI(裁剪页返回后经 onPageShow 落到 photoUri) */
  private pendingPickUri: string = '';

  // 设备侧表盘文件
  @State dialFiles: DeviceDialFile[] = [];
  @State currentDialPath: string = '';

  // 排查日志面板：经 LogSink 实时收取 SDK 日志（仅本页生命周期内生效）
  @State dialLogLines: string[] = [];
  @State showDialLog: boolean = false;
  private dialLogSink: LogSink | null = null;

  aboutToAppear(): void {
    VPBleSDK.getInstance().on(SDKEventType.UI_STYLE_CHANGED, this.uiPushHandler);
    this.dialLogSink = (level: LogLevel, tag: string, msg: string): void => {
      this.pushDialLog(`${this.levelName(level)} ${tag}: ${msg}`);
    };
    Logger.setSink(this.dialLogSink);
  }

  aboutToDisappear(): void {
    VPBleSDK.getInstance().off(SDKEventType.UI_STYLE_CHANGED, this.uiPushHandler);
    Logger.setSink(null);
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  /** 承接裁剪页返回的裁剪结果 */
  onPageShow(): void {
    const params = router.getParams() as Record<string, string>;
    const cropFilePath = params?.['cropFilePath'];
    if (cropFilePath) {
      this.photoUri = cropFilePath;
      this.showToastMsg('已裁剪,可传输照片表盘');
    }
  }

  private levelName(level: LogLevel): string {
    switch (level) {
      case LogLevel.DEBUG: return 'D';
      case LogLevel.INFO: return 'I';
      case LogLevel.WARN: return 'W';
      case LogLevel.ERROR: return 'E';
      default: return '?';
    }
  }

  private nowStamp(): string {
    const d = new Date();
    const p = (n: number, w: number): string => n.toString().padStart(w, '0');
    return `${p(d.getHours(), 2)}:${p(d.getMinutes(), 2)}:${p(d.getSeconds(), 2)}.${p(d.getMilliseconds(), 3)}`;
  }

  private pushDialLog(line: string): void {
    this.dialLogLines.push(`${this.nowStamp()} ${line}`);
    if (this.dialLogLines.length > 400) {
      this.dialLogLines.splice(0, this.dialLogLines.length - 400);
    }
  }

  private clampInt(s: string, min: number, max: number, def: number): number {
    const n = parseInt(s, 10);
    if (isNaN(n)) {
      return def;
    }
    return Math.max(min, Math.min(max, n));
  }

  private hex2(n: number): string {
    return n.toString(16).padStart(2, '0');
  }

  private colorHex(): string {
    return `#${this.hex2(this.clampInt(this.bgR, 0, 255, 0))}`
      + `${this.hex2(this.clampInt(this.bgG, 0, 255, 0))}`
      + `${this.hex2(this.clampInt(this.bgB, 0, 255, 0))}`;
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

  private dataTypeText(dt?: DialDataType): string {
    switch (dt) {
      case DialDataType.MARKET: return '市场表盘';
      case DialDataType.PHOTO: return '照片/背景表盘';
      case DialDataType.TOTAL_UI: return '全套 UI';
      default: return '--';
    }
  }

  /** 自定义背景参数——「保存」与照片表盘传输收尾共用 */
  private buildBgParams(): CustomBgDialParams {
    return {
      isDefaultBg: this.bgDefault ? 1 : 0,
      timePosition: this.clampInt(this.bgTimePos, 0, 7, 1),
      timeTopPosition: this.clampInt(this.bgTimeTop, 0, 7, 1),
      timeBottomPosition: this.clampInt(this.bgTimeBottom, 0, 7, 0),
      timeColor: [
        this.clampInt(this.bgR, 0, 255, 255),
        this.clampInt(this.bgG, 0, 255, 255),
        this.clampInt(this.bgB, 0, 255, 255),
      ],
    };
  }

  private async readDial(dt: DialDataType): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const svc = VPBleSDK.getInstance().dialService;
      const r = dt === DialDataType.MARKET ? await svc.readMarketDial()
        : dt === DialDataType.PHOTO ? await svc.readPhotoDial()
          : await svc.readTotalDialInfo();
      this.dialResult = r;
      if (!r.success) {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  // ==================== 市场表盘传输 ====================

  /**
   * 选择 .bin 并传输。通道自动分流：有杰理 RCSP 服务走 transferMarketDial
   * （传完 SDK 自动设为当前表盘）；无（中科设备）走 transferZKMarketDial
   * （中科设备通道，内部含读信息 + 进入传输态）。
   */
  private async pickMarketBin(): Promise<void> {
    if (this.marketTransferring || this.isWriting) {
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.bin'];
      const uris = await docPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let buf: ArrayBuffer;
      try {
        const stat = fs.statSync(file.path);
        buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        this.marketFileSize = stat.size;
      } finally {
        fs.closeSync(file);
      }
      this.marketBin = buf;
      this.marketFileName = this.extractName(uri);
      await this.startMarketTransfer();
    } catch (err) {
      this.showToastMsg(`读取文件失败：${(err as Error).message}`);
    }
  }

  private async startMarketTransfer(): Promise<void> {
    if (!this.marketBin) {
      return;
    }
    this.marketTransferring = true;
    this.marketProgress = 0;
    this.marketStatus = '准备传输...';
    const sdk = VPBleSDK.getInstance();
    const useJl = sdk.hasJlRcspService();
    try {
      if (useJl) {
        // 设备只保留一个已下载市场表盘槽：传输前先删旧表盘，否则设备拒收新表盘
        // （错误信息 "don't have internal slot"）
        const removed = await sdk.dialService.deleteDownloadedMarketDial();
        if (!removed) {
          this.marketTransferring = false;
          this.marketStatus = '删除旧市场表盘失败';
          this.showToastMsg('删除设备上旧市场表盘失败，已中止传输');
          return;
        }
      }
      this.marketProgress = 0;
      this.marketStatus = '传输中...';
      const onTransfer = (state: DialTransferState, progress: number, message?: string): void => {
        this.marketProgress = Math.min(100, Math.round(progress));
        if (state === DialTransferState.TRANSMISSION) {
          this.marketStatus = `传输中 ${this.marketProgress}%`;
        } else if (state === DialTransferState.SUCCESSFUL) {
          this.marketTransferring = false;
          this.marketStatus = '传输成功（已设为当前表盘）';
          // SDK 已把该文件设为设备当前表盘，此命令负责把屏显切到市场表盘
          sdk.dialService.setCustomUIStyle(1, UIStyleType.CUSTOM).catch((err: Error): void => {
            this.showToastMsg(`切屏失败：${err.message}`);
          });
          this.showToastMsg('市场表盘传输成功');
          this.refreshDialFiles();
        } else if (state === DialTransferState.FAIL) {
          this.marketTransferring = false;
          // 设备侧报 "don't have internal slot" 时为表盘资源表已满，引导用户手动清理
          const slotFull = (message ?? '').toLowerCase().includes('slot');
          this.marketStatus = `传输失败${message ? '：' + message : ''}`
            + (slotFull ? '（设备表盘槽位已满，请在「设备表盘文件」中删除不需要的表盘后重试）' : '');
          this.showToastMsg(slotFull ? '设备表盘槽位已满：请先在「设备表盘文件」中删除不需要的表盘'
            : `市场表盘传输失败：${message ?? '未知'}`);
        }
      };
      if (useJl) {
        const r = sdk.dialService.transferMarketDial(
          this.marketBin, this.marketFileName || `DIAL_${Date.now()}.BIN`, onTransfer);
        if (!r.success) {
          this.marketTransferring = false;
          this.marketStatus = `无法启动：${r.errorMessage ?? '未知'}`;
          this.showToastMsg(`市场表盘传输失败：${r.errorMessage ?? '未知'}`);
        }
      } else {
        sdk.dialService.transferZKMarketDial(this.marketBin, onTransfer).catch((err: Error) => {
          this.marketTransferring = false;
          this.marketStatus = `异常：${err.message}`;
          this.showToastMsg(`市场表盘传输异常：${err.message}`);
        });
      }
    } catch (err) {
      // 启动阶段的任何异常都必须浮出水面（此前会被外层误报成"下载失败"）
      console.error(`[DialPage] startMarketTransfer 异常：${(err as Error).message}`);
      this.marketTransferring = false;
      this.marketStatus = `传输启动异常：${(err as Error).message}`;
      this.showToastMsg(`市场表盘传输启动异常：${(err as Error).message}`);
    }
  }

  // ==================== 网络市场表盘列表 ====================

  /**
   * 拉取网络市场表盘目录（分页）。表盘能力参数（dialShape/binProtocol/maxLength）
   * 优先复用「表盘信息读取」的结果，未读过时自动现读一次市场表盘信息。
   */
  private async fetchNetDialList(loadMore: boolean): Promise<void> {
    if (this.netDialLoading || this.marketTransferring) {
      return;
    }
    let market = this.dialResult?.market;
    if (!market) {
      await this.readDial(DialDataType.MARKET);
      market = this.dialResult?.market;
    }
    if (!market) {
      this.netDialStatus = '缺少市场表盘信息（读取失败）';
      this.showToastMsg('请先成功读取市场表盘信息');
      return;
    }
    this.netDialLoading = true;
    this.netDialStatus = '获取中...';
    try {
      const pageIndex = loadMore ? this.netDialPageIndex + 1 : 1;
      const r = await VPBleSDK.getInstance().dialService.fetchNetworkDialList({
        dialShape: market.dialShape,
        binProtocol: market.binProtocol,
        maxLength: market.writeDataLength,
        pageIndex: pageIndex,
        pageSize: 12,
      });
      if (!r.success) {
        this.netDialStatus = `获取失败：${r.errorMessage ?? '未知'}`;
        this.showToastMsg(`获取网络表盘失败：${r.errorMessage ?? '未知'}`);
        return;
      }
      this.netDialPageIndex = pageIndex;
      this.netDialCounts = r.counts;
      this.netDialItems = loadMore ? this.netDialItems.concat(r.items) : r.items;
      this.netDialStatus = `共 ${r.counts} 个，已加载 ${this.netDialItems.length} 个（点击条目下载并传输）`;
    } catch (err) {
      this.netDialStatus = `获取异常：${(err as Error).message}`;
    } finally {
      this.netDialLoading = false;
    }
  }

  /** 下载选中的网络表盘 .bin，完成后复用市场表盘传输通道下发 */
  private async downloadAndTransferNetDial(item: NetworkDialItem): Promise<void> {
    if (this.marketTransferring || this.netDialLoading) {
      return;
    }
    this.marketTransferring = true;
    this.marketProgress = 0;
    this.marketFileName = this.extractName(item.fileUrl);
    this.marketFileSize = item.fileLength;
    this.marketStatus = '下载中...';
    // 阶段一：下载（失败归"下载失败"）
    let data: ArrayBuffer;
    try {
      const dl = await VPBleSDK.getInstance().dialService.downloadNetworkDialFile(item.fileUrl);
      if (!dl.success || !dl.data) {
        throw new Error(dl.errorMessage ?? '未知');
      }
      data = dl.data;
    } catch (err) {
      console.error(`[DialPage] 下载失败：${(err as Error).message}`);
      this.marketTransferring = false;
      this.marketStatus = `下载失败：${(err as Error).message}`;
      this.showToastMsg(`表盘下载失败：${(err as Error).message}`);
      return;
    }
    this.marketBin = data;
    // 阶段二：传输（异常单独归"传输异常"，不与下载混淆）
    try {
      await this.startMarketTransfer();
    } catch (err) {
      const e = err as Error;
      console.error(`[DialPage] 市场表盘传输异常：${e.message}`);
      this.marketTransferring = false;
      this.marketStatus = `传输异常：${e.message}`;
      this.showToastMsg(`市场表盘传输异常：${e.message}`);
    }
  }

  // ==================== 照片表盘传输（杰理双图） ====================

  /** 读取设备上报屏幕尺寸，填充主图/缩略图默认尺寸 */
  private async readScreenSize(): Promise<void> {
    if (this.photoTransferring || this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const s = await VPBleSDK.getInstance().dialService.getDialScreenSize();
      this.mainW = `${s.width}`;
      this.mainH = `${s.height}`;
      this.smallW = `${s.width}`;
      this.smallH = `${s.height}`;
      this.showToastMsg(`屏幕尺寸 ${s.width}x${s.height}`);
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  /** 选照片 → 裁剪页(按主图比例取景,圆形表盘椭圆框);裁剪结果经 onPageShow 回来 */
  private async pickPhoto(): Promise<void> {
    if (this.photoTransferring) {
      return;
    }
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
      };
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(opts);
      if (!result.photoUris || result.photoUris.length === 0) {
        return;
      }
      this.pendingPickUri = result.photoUris[0];
      router.pushUrl({
        url: 'pages/subPages/PhotoCropPage',
        params: {
          srcUri: this.pendingPickUri,
          ratioW: this.clampInt(this.mainW, 1, 4096, 1),
          ratioH: this.clampInt(this.mainH, 1, 4096, 1),
          isCircle: this.photoIsCircle,
        },
      });
    } catch (err) {
      this.showToastMsg(`选择照片失败：${(err as Error).message}`);
    }
  }

  /**
   * 按机型查尺寸:读设备照片表盘信息取自定义表盘类型,查 SDK 内置尺寸表回填
   * 主图/小图尺寸与圆形标志。表外类型回退提示手填。
   */
  private async fillSizeFromTable(): Promise<void> {
    if (this.photoTransferring || this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().dialService.readPhotoDial();
      if (!r.success || !r.photo) {
        this.showToastMsg(`读取照片表盘信息失败：${r.errorMessage ?? '未知'}`);
        return;
      }
      const cfg = findPhotoDialSize(r.photo.customDialType);
      if (!cfg) {
        this.photoSizeNote = `表内无该机型(${r.photo.customDialType}),请按规格表手填`;
        this.showToastMsg('尺寸表未收录该机型,请手填');
        return;
      }
      this.mainW = `${cfg.mainWidth}`;
      this.mainH = `${cfg.mainHeight}`;
      this.smallW = `${cfg.smallCanvasWidth}`;
      this.smallH = `${cfg.smallCanvasHeight}`;
      this.photoIsCircle = cfg.isCircle;
      this.photoSizeNote = `已按机型回填:主图 ${cfg.mainWidth}×${cfg.mainHeight},`
        + `小图 ${cfg.smallCanvasWidth}×${cfg.smallCanvasHeight}${cfg.isCircle ? ',圆形表盘' : ''}`;
      this.showToastMsg('尺寸已回填');
    } catch (err) {
      this.showToastMsg(`查尺寸异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  /**
   * 照片表盘传输：图片 → convertDialPhotoToBmp（主图 + 缩略图）→ transferCustomBgDialPair。
   * 成功后稍候把设备屏显切到照片表盘槽，并下发时间元素（沿用「自定义背景」卡片参数）。
   */
  private async transferPhoto(): Promise<void> {
    if (this.photoTransferring || !this.photoUri) {
      return;
    }
    this.photoTransferring = true;
    this.photoProgress = 0;
    this.photoStatus = '图片转换中...';
    try {
      const svc = VPBleSDK.getInstance().dialService;
      const workDir = `${(getContext(this) as common.Context).filesDir}/CustomDial`;
      const mainW = this.clampInt(this.mainW, 1, 2048, 240);
      const mainH = this.clampInt(this.mainH, 1, 2048, 240);
      const smallW = this.clampInt(this.smallW, 1, 2048, 240);
      const smallH = this.clampInt(this.smallH, 1, 2048, 240);

      const main = await svc.convertDialPhotoToBmp(this.photoUri, workDir, mainW, mainH);
      if (!main.success || !main.data) {
        throw new Error(`主图转换失败：${main.errorMessage ?? '未知'}`);
      }
      this.photoStatus = '缩略图转换中...';
      // 圆形表盘小图:透明区铺黑底(设备端兼容);裁剪页已把椭圆外置透明
      const small = await svc.convertDialPhotoToBmp(this.photoUri, workDir, smallW, smallH,
        undefined, this.photoIsCircle);
      if (!small.success || !small.data) {
        throw new Error(`缩略图转换失败：${small.errorMessage ?? '未知'}`);
      }
      this.photoStatus = '传输中...';
      const r = svc.transferCustomBgDialPair(small.data, main.data,
        (state: DialTransferState, progress: number, message?: string): void => {
          this.photoProgress = Math.min(100, Math.round(progress));
          if (state === DialTransferState.TRANSMISSION) {
            this.photoStatus = `传输中 ${this.photoProgress}%`;
          } else if (state === DialTransferState.SUCCESSFUL) {
            this.photoTransferring = false;
            this.photoProgress = 100;
            this.photoStatus = '传输成功（两图已激活）';
            this.showToastMsg('照片表盘传输成功，正在切屏...');
            setTimeout((): void => {
              // 把设备屏显切到照片表盘槽（UIStyleType.OTHER）
              svc.setCustomUIStyle(1, UIStyleType.OTHER).catch((err: Error): void => {
                this.showToastMsg(`切屏失败：${err.message}`);
              });
              // 时间位置/颜色（沿用「自定义背景」卡片的参数）
              svc.setCustomBackground(this.buildBgParams()).catch((err: Error): void => {
                this.showToastMsg(`设置时间元素失败：${err.message}`);
              });
            }, 150);
          } else if (state === DialTransferState.FAIL) {
            this.photoTransferring = false;
            this.photoStatus = `传输失败${message ? '：' + message : ''}`;
            this.showToastMsg(`照片表盘传输失败：${message ?? '未知'}`);
          }
        });
      if (!r.success) {
        throw new Error(r.errorMessage ?? '无法启动传输');
      }
    } catch (err) {
      this.photoTransferring = false;
      this.photoStatus = `失败：${(err as Error).message}`;
      this.showToastMsg(`照片表盘失败：${(err as Error).message}`);
    }
  }

  // ==================== 中科照片表盘传输 ====================

  /**
   * 中科设备照片表盘:裁剪图 → 主图/小图各转通道编码 → 拼整包 → transferZKPhotoDial
   * (SDK 内部完成 读信息/进传输态/通道传输/收尾时间元素)。569 系列需打开开关。
   * 569 方屏的圆角裁剪本 demo 未做(宿主可按机型规格自加)。
   */
  private async transferZKPhoto(): Promise<void> {
    if (this.photoTransferring || !this.photoUri) {
      return;
    }
    this.photoTransferring = true;
    this.photoProgress = 0;
    this.photoStatus = '主图编码中...';
    try {
      const svc = VPBleSDK.getInstance().dialService;
      const mainW = this.clampInt(this.mainW, 1, 2048, 240);
      const mainH = this.clampInt(this.mainH, 1, 2048, 240);
      const smallW = this.clampInt(this.smallW, 1, 2048, 240);
      const smallH = this.clampInt(this.smallH, 1, 2048, 240);

      const main = await svc.convertZKPhotoImageToPar(this.photoUri, mainW, mainH, this.isZK569x);
      if (!main.success || !main.data) {
        throw new Error(`主图编码失败：${main.errorMessage ?? '未知'}`);
      }
      this.photoStatus = '小图编码中...';
      const small = await svc.convertZKPhotoImageToPar(this.photoUri, smallW, smallH, this.isZK569x);
      if (!small.success || !small.data) {
        throw new Error(`小图编码失败：${small.errorMessage ?? '未知'}`);
      }
      this.photoStatus = '传输中...';
      const payload = svc.buildZKPhotoDialPayload(main.data, small.data);
      const r = await svc.transferZKPhotoDial(payload,
        (state: DialTransferState, progress: number, message?: string): void => {
          this.photoProgress = Math.min(100, Math.round(progress));
          if (state === DialTransferState.TRANSMISSION) {
            this.photoStatus = `传输中 ${this.photoProgress}%`;
          } else if (state === DialTransferState.SUCCESSFUL) {
            this.photoTransferring = false;
            this.photoProgress = 100;
            this.photoStatus = '传输成功';
            this.showToastMsg('中科照片表盘传输成功');
          } else if (state === DialTransferState.FAIL) {
            this.photoTransferring = false;
            this.photoStatus = `传输失败${message ? '：' + message : ''}`;
            this.showToastMsg(`中科照片表盘传输失败：${message ?? '未知'}`);
          }
        });
      if (!r.success) {
        throw new Error(r.errorMessage ?? '无法启动传输');
      }
    } catch (err) {
      this.photoTransferring = false;
      this.photoStatus = `失败：${(err as Error).message}`;
      this.showToastMsg(`中科照片表盘失败：${(err as Error).message}`);
    }
  }

  // ==================== 设备侧表盘文件 ====================

  private async refreshDialFiles(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const svc = VPBleSDK.getInstance().dialService;
      const list = await svc.getDialFileList();
      const cur = await svc.getCurrentDial();
      this.dialFiles = list.list ?? [];
      this.currentDialPath = cur.dial?.path ?? '';
      if (!list.success) {
        this.showToastMsg(`读取列表失败：${list.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async useDial(f: DeviceDialFile): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const ok = await VPBleSDK.getInstance().dialService.setUsingDial(f);
      this.showToastMsg(ok ? `已切换到 ${f.fileName}` : '切换失败（设备拒绝）');
    } catch (err) {
      this.showToastMsg(`切换异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
    await this.refreshDialFiles();
  }

  private async deleteDialRow(f: DeviceDialFile): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const ok = await VPBleSDK.getInstance().dialService.deleteDial(f);
      this.showToastMsg(ok ? `已删除 ${f.fileName}` : '删除失败（设备拒绝）');
    } catch (err) {
      this.showToastMsg(`删除异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
    await this.refreshDialFiles();
  }

  // ==================== 自定义背景 / UI 风格 ====================

  private async saveBg(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().dialService.setCustomBackground(this.buildBgParams());
      this.showToastMsg(r.success ? '自定义背景已保存' : `保存失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`保存异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async uiRead(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().dialService
        .readCustomUIStyle(this.clampInt(this.uiStyle, 0, 65535, 0), this.uiStyleType);
      this.uiResult = r;
      if (!r.success) {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async uiSet(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().dialService
        .setCustomUIStyle(this.clampInt(this.uiStyle, 0, 65535, 0), this.uiStyleType);
      this.uiResult = r;
      this.showToastMsg(r.success ? 'UI 风格已设置' : `设置失败：${r.errorMessage ?? '未知'}`);
    } catch (err) {
      this.showToastMsg(`设置异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
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
          Text('表盘与 UI').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.DialInfoCard()
            this.MarketTransferCard()
            this.NetworkDialCard()
            this.PhotoTransferCard()
            this.ZkPhotoCard()
            this.DialFileListCard()
            this.CustomBgCard()
            this.UIStyleCard()
            this.DialLogCard()
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
  DialInfoCard() {
    Column({ space: 12 }) {
      Text('表盘信息读取').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')
      Row() {
        Button('市场表盘').fontSize(13).height(34).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.readDial(DialDataType.MARKET))
        Blank().width(8)
        Button('照片表盘').fontSize(13).height(34).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.readDial(DialDataType.PHOTO))
        Blank().width(8)
        Button('全套 UI').fontSize(13).height(34).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.readDial(DialDataType.TOTAL_UI))
      }.width('100%')

      if (this.dialResult) {
        Divider().color('#F0F0F0').margin({ top: 4, bottom: 4 })
        Text(`类型：${this.dataTypeText(this.dialResult.dataType)}`)
          .fontSize(13).fontColor('#999999').width('100%')
        if (this.dialResult.market) {
          this.MetricRow('写入地址', `0x${this.dialResult.market.dataAddress.toString(16).toUpperCase()}`)
          this.MetricRow('写入长度', `${this.dialResult.market.writeDataLength}`)
          this.MetricRow('bin 协议', `${this.dialResult.market.binProtocol}`)
          this.MetricRow('表盘形状', `${this.dialResult.market.dialShape}`)
          this.MetricRow('表盘 ID', `${this.dialResult.market.imageId}`)
        }
        if (this.dialResult.photo) {
          this.MetricRow('写入地址', `0x${this.dialResult.photo!.dataAddress.toString(16).toUpperCase()}`)
          this.MetricRow('写入长度', `${this.dialResult.photo!.writeDataLength}`)
          this.MetricRow('自定义类型', `${this.dialResult.photo!.customDialType}`)
          this.MetricRow('时间位置', `${this.dialResult.photo!.timePosition}（顶 ${this.dialResult.photo!.timeTopPosition} / 底 ${this.dialResult.photo!.timeBottomPosition}）`)
          this.MetricRow('元素颜色', `RGB(${this.dialResult.photo!.elementColor[0]}, ${this.dialResult.photo!.elementColor[1]}, ${this.dialResult.photo!.elementColor[2]})`)
          this.MetricRow('背景 CRC', `0x${this.dialResult.photo!.bgCrc.toString(16).toUpperCase()}`)
        }
        if (this.dialResult.total) {
          this.MetricRow('写入地址', `0x${this.dialResult.total.dataAddress.toString(16).toUpperCase()}`)
          this.MetricRow('写入长度', `${this.dialResult.total.writeDataLength}`)
        }
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  MarketTransferCard() {
    Column({ space: 12 }) {
      Text('市场表盘传输').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')
      Row() {
        Column() {
          Text(this.marketFileName || '未选择 .bin 文件').fontSize(14)
            .fontColor(this.marketFileName ? '#333333' : '#BBBBBB')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.marketFileSize > 0) {
            Text(this.formatBytes(this.marketFileSize)).fontSize(12).fontColor('#999999').margin({ top: 2 })
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('选择并传输').fontSize(13).height(36)
          .backgroundColor(this.marketTransferring ? '#CCCCCC' : '#007DFF')
          .fontColor(Color.White).borderRadius(6)
          .enabled(!this.marketTransferring)
          .onClick(() => this.pickMarketBin())
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.marketStatus !== '') {
        Column({ space: 6 }) {
          Progress({ value: this.marketProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.marketProgress >= 100 ? '#34C759' : '#007DFF')
            .backgroundColor('#E5E5E5').borderRadius(2)
          Text(this.marketStatus).fontSize(12).fontColor('#999999').width('100%')
        }.width('100%')
      }

      Text('通道自动选择：有杰理 RCSP 服务走 transferMarketDial（传完自动设为当前表盘），'
        + '否则走 transferZKMarketDial（中科设备）。.bin 须与设备表盘规格匹配。')
        .fontSize(11).fontColor('#BBBBBB').width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  NetworkDialCard() {
    Column({ space: 10 }) {
      Row() {
        Text('网络市场表盘').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
          .layoutWeight(1)
        Button('加载更多').fontSize(12).height(32)
          .backgroundColor('#666666').fontColor(Color.White).borderRadius(6)
          .enabled(!this.netDialLoading && !this.marketTransferring
            && this.netDialItems.length > 0 && this.netDialItems.length < this.netDialCounts)
          .margin({ right: 6 })
          .onClick(() => this.fetchNetDialList(true))
        Button(this.netDialLoading ? '获取中...' : '获取列表').fontSize(12).height(32)
          .backgroundColor(this.netDialLoading ? '#CCCCCC' : '#007DFF')
          .fontColor(Color.White).borderRadius(6)
          .enabled(!this.netDialLoading && !this.marketTransferring)
          .onClick(() => this.fetchNetDialList(false))
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.netDialStatus !== '') {
        Text(this.netDialStatus).fontSize(12).fontColor('#999999').width('100%')
      }

      ForEach(this.netDialItems, (item: NetworkDialItem) => {
        Row() {
          Image(item.previewUrl)
            .width(40).height(40).borderRadius(4)
            .objectFit(ImageFit.Cover)
            .backgroundColor('#F0F0F0')
          Column({ space: 2 }) {
            Text(item.name).fontSize(13).fontColor('#333333')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`CRC ${item.crc} · ${this.formatBytes(item.fileLength)}`)
              .fontSize(11).fontColor('#999999')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })
          Button('下载传输').fontSize(12).height(30)
            .backgroundColor('#FF9500').fontColor(Color.White).borderRadius(6)
            .enabled(!this.netDialLoading && !this.marketTransferring)
            .onClick(() => this.downloadAndTransferNetDial(item))
        }.width('100%').alignItems(VerticalAlign.Center)
        .padding({ top: 6, bottom: 6 })
        .border({ width: { bottom: 0.5 }, color: '#F0F0F0' })
      }, (item: NetworkDialItem) => item.fileUrl)

      if (this.marketTransferring) {
        Progress({ value: this.marketProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .color(this.marketProgress >= 100 ? '#34C759' : '#FF9500')
          .backgroundColor('#E5E5E5').borderRadius(2)
      }

      Text('列表按当前设备市场表盘能力（形状/协议/可写长度）从服务端过滤；'
        + '点击条目自动下载 .bin 并走「市场表盘传输」通道下发。需设备网络可用。')
        .fontSize(11).fontColor('#BBBBBB').width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  PhotoTransferCard() {
    Column({ space: 10 }) {
      Row() {
        Text('照片表盘传输').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
          .layoutWeight(1)
        if (this.photoIsCircle) {
          Text('圆形表盘').fontSize(10).fontColor('#007DFF')
            .border({ width: 1, color: '#007DFF' }).borderRadius(4)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        }
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text(this.photoUri ? this.extractName(this.photoUri) : '未选择照片(选图后自动进裁剪页)').fontSize(13)
          .fontColor(this.photoUri ? '#333333' : '#BBBBBB')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button('选择照片').fontSize(13).height(36)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.photoTransferring)
          .onClick(() => this.pickPhoto())
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('主图 W×H').fontSize(13).fontColor('#666666').width(76)
        TextInput({ text: this.mainW }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.mainW = v; })
        Text('×').fontSize(13).fontColor('#999999').margin({ left: 6, right: 6 })
        TextInput({ text: this.mainH }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.mainH = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('小图 W×H').fontSize(13).fontColor('#666666').width(76)
        TextInput({ text: this.smallW }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.smallW = v; })
        Text('×').fontSize(13).fontColor('#999999').margin({ left: 6, right: 6 })
        TextInput({ text: this.smallH }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.smallH = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.photoSizeNote !== '') {
        Text(this.photoSizeNote).fontSize(11).fontColor('#007DFF').width('100%')
      }

      Row() {
        Button('按机型查尺寸').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting && !this.photoTransferring)
          .onClick(() => this.fillSizeFromTable())
        Blank().width(8)
        Button('读屏幕尺寸').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor('#666666').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting && !this.photoTransferring)
          .onClick(() => this.readScreenSize())
      }.width('100%')

      Button(this.photoTransferring ? '传输中...' : '传输照片表盘(杰理)').fontSize(13).height(40)
        .width('100%')
        .backgroundColor(this.photoTransferring || !this.photoUri ? '#CCCCCC' : '#FF9500')
        .fontColor(Color.White).borderRadius(8)
        .enabled(!this.photoTransferring && this.photoUri !== '')
        .onClick(() => this.transferPhoto())

      if (this.photoStatus !== '') {
        Column({ space: 6 }) {
          Progress({ value: this.photoProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.photoProgress >= 100 ? '#34C759' : '#FF9500')
            .backgroundColor('#E5E5E5').borderRadius(2)
          Text(this.photoStatus).fontSize(12).fontColor('#999999').width('100%')
        }.width('100%')
      }

      Text('推荐流程:先「按机型查尺寸」(设备上报类型 → SDK 内置尺寸表回填),再选照片进裁剪页'
        + '(按主图比例取景,圆形表盘椭圆框)。SDK 串行传输小图+主图并都激活,传输前自动切回出厂'
        + '照片槽,成功后自动切屏并下发时间元素(沿用「自定义背景」卡片参数)。圆形表盘小图自动铺黑底; '
        + '带边框效果需宿主在裁剪图上自行合成。')
        .fontSize(11).fontColor('#BBBBBB').width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  ZkPhotoCard() {
    Column({ space: 10 }) {
      Text('中科照片表盘').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      Row() {
        Text('569 系列').fontSize(13).fontColor('#666666').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.isZK569x })
          .selectedColor('#007DFF')
          .onChange((on: boolean) => { this.isZK569x = on; })
      }.width('100%')

      Text('与上方卡片共用照片与尺寸(建议先「按机型查尺寸」)。主图/小图分别编码后拼整包,'
        + '由 SDK 完成读信息、进传输态、通道传输与时间元素收尾。569 方屏的圆角裁剪本 demo 未做。')
        .fontSize(11).fontColor('#BBBBBB').width('100%')

      Button(this.photoTransferring ? '传输中...' : '传输照片表盘(中科)').fontSize(13).height(40)
        .width('100%')
        .backgroundColor(this.photoTransferring || !this.photoUri ? '#CCCCCC' : '#FF9500')
        .fontColor(Color.White).borderRadius(8)
        .enabled(!this.photoTransferring && this.photoUri !== '')
        .onClick(() => this.transferZKPhoto())
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  DialFileListCard() {
    Column({ space: 10 }) {
      Row() {
        Text('设备表盘文件').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
          .layoutWeight(1)
        Button(this.isWriting ? '读取中...' : '读取列表').fontSize(13).height(32)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.refreshDialFiles())
      }.width('100%').alignItems(VerticalAlign.Center)

      if (this.dialFiles.length === 0) {
        Text('暂无数据（读取列表后展示，需设备支持 JL RCSP 服务）')
          .fontSize(12).fontColor('#BBBBBB').width('100%')
      } else {
        ForEach(this.dialFiles, (f: DeviceDialFile) => {
          Row() {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(f.fileName).fontSize(13).fontColor('#333333')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (f.path === this.currentDialPath) {
                  Text('当前').fontSize(10).fontColor('#34C759')
                    .border({ width: 1, color: '#34C759' }).borderRadius(4)
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                }
              }.alignItems(VerticalAlign.Center)
              Text(`uuid=${f.uuid}`).fontSize(11).fontColor('#999999')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)

            Button('使用').fontSize(12).height(30)
              .backgroundColor('#34C759').fontColor(Color.White).borderRadius(6)
              .enabled(!this.isWriting && f.path !== this.currentDialPath)
              .margin({ right: 6 })
              .onClick(() => this.useDial(f))
            Button('删除').fontSize(12).height(30)
              .backgroundColor('#E84026').fontColor(Color.White).borderRadius(6)
              .enabled(!this.isWriting)
              .onClick(() => this.deleteDialRow(f))
          }.width('100%').alignItems(VerticalAlign.Center)
          .padding({ top: 6, bottom: 6 })
          .border({ width: { bottom: 0.5 }, color: '#F0F0F0' })
        }, (f: DeviceDialFile) => f.path)
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  CustomBgCard() {
    Column({ space: 10 }) {
      Text('自定义背景').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      Row() {
        Text('设为默认表盘').fontSize(13).fontColor('#666666').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.bgDefault })
          .selectedColor('#007DFF')
          .onChange((on: boolean) => { this.bgDefault = on; })
      }.width('100%')

      Row() {
        Text('时间位置（0-7）').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.bgTimePos }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgTimePos = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('顶部时间位置（0-7）').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.bgTimeTop }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgTimeTop = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('底部时间位置（0-7）').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.bgTimeBottom }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgTimeBottom = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('时间颜色 RGB').fontSize(13).fontColor('#666666').layoutWeight(1)
        Row().width(24).height(24).backgroundColor(this.colorHex()).borderRadius(4)
          .border({ width: 1, color: '#E0E0E0' })
      }.width('100%')
      Row() {
        Text('R').fontSize(13).fontColor('#666666').width(20)
        TextInput({ text: this.bgR }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgR = v; })
        Blank().width(8)
        Text('G').fontSize(13).fontColor('#666666').width(20)
        TextInput({ text: this.bgG }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgG = v; })
        Blank().width(8)
        Text('B').fontSize(13).fontColor('#666666').width(20)
        TextInput({ text: this.bgB }).layoutWeight(1).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.bgB = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Button('保存').width('100%').height(40)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(8)
        .enabled(!this.isWriting)
        .onClick(() => this.saveBg())

      Text('时间位置可用值与屏形相关：圆形屏/带屏(窄长方屏,主图高宽比>1.4)仅 1=上 2=中 3=下;'
        + '方屏/矩形屏(高宽比≤1.4)才有 4=左上 5=右上 6=左下 7=右下。'
        + '可在「照片表盘传输」卡「按机型查尺寸」后按查到的屏形选择。')
        .fontSize(11).fontColor('#BBBBBB').width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  UIStyleCard() {
    Column({ space: 10 }) {
      Text('UI 风格设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%')

      Row() {
        Text('style').fontSize(13).fontColor('#666666').layoutWeight(1)
        TextInput({ text: this.uiStyle }).width(90).height(36).type(InputType.Number)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.uiStyle = v; })
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text('styleType').fontSize(13).fontColor('#666666').width(72)
        this.StyleTypeTab(UIStyleType.FACTORY, '出厂')
        this.StyleTypeTab(UIStyleType.CUSTOM, '自定义')
        this.StyleTypeTab(UIStyleType.OTHER, '其他')
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Button('读取').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#34C759').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.uiRead())
        Blank().width(8)
        Button('设置').fontSize(13).height(36).layoutWeight(1)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#FF9500').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.uiSet())
      }.width('100%')

      if (this.uiResult) {
        Divider().color('#F0F0F0').margin({ top: 4, bottom: 4 })
        this.MetricRow('ack', this.uiResult.ack !== undefined ? `${this.uiResult.ack}` : '--')
        this.MetricRow('style', this.uiResult.style !== undefined ? `${this.uiResult.style}` : '--')
        this.MetricRow('styleType', this.uiResult.styleType !== undefined ? `${this.uiResult.styleType}` : '--')
        if (this.uiResult.control === UIStyleControl.READ_MULTI && this.uiResult.data
          && this.uiResult.data.length > 0) {
          this.MetricRow('数据', this.uiResult.data.join(', '))
        }
      }
      if (this.lastUiPush !== '--') {
        this.MetricRow('最近设备推送', this.lastUiPush)
      }
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16, top: 12, bottom: 16 })
  }

  @Builder
  StyleTypeTab(t: UIStyleType, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.uiStyleType === t ? Color.White : '#666666')
      .backgroundColor(this.uiStyleType === t ? '#007DFF' : '#F0F0F0')
      .borderRadius(6)
      .height(28)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .margin({ left: 6 })
      .onClick(() => { this.uiStyleType = t; })
  }

  @Builder
  MetricRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#666666').layoutWeight(1)
      Text(value).fontSize(13).fontColor('#333333').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '62%' })
    }.width('100%').height(40)
  }

  /** 排查日志面板：实时展示本页期间收到的 SDK 日志（最新在上），便于现场反馈问题 */
  @Builder
  DialLogCard() {
    Column({ space: 8 }) {
      Row() {
        Text('排查日志（SDK 实时输出）').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
          .layoutWeight(1)
        Text(`${this.dialLogLines.length} 条`).fontSize(12).fontColor('#999999').margin({ right: 8 })
        Text(this.showDialLog ? '收起' : '展开').fontSize(13).fontColor('#007DFF')
          .onClick(() => {
            this.showDialLog = !this.showDialLog;
          })
      }.width('100%')
      if (this.showDialLog) {
        Scroll() {
          Column() {
            ForEach(this.dialLogLines.slice(-120).reverse(), (line: string, idx: number) => {
              Text(line)
                .fontSize(10)
                .fontColor('#444444')
                .maxLines(3)
                .width('100%')
                .padding({ top: 1, bottom: 1 })
            }, (line: string, idx: number): string => `${idx}_${line}`)
          }.width('100%')
        }
        .width('100%').height(240).backgroundColor('#FFFFFF').borderRadius(8).padding(8)
        .align(Alignment.Top)
      }
      Text('传输失败时展开此面板并截图，即可看到删除清单/传输文件名/设备错误码等关键日志')
        .fontSize(11).fontColor('#999999').width('100%')
    }.width('100%')
  }
}

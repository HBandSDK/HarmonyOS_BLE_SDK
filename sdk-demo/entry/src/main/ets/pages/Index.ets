import { VPBleSDK, SDK_VERSION, ConnectionState, SDKEventType, SDKResult, UserProfile, GoalConfig, BtState, LogLevel, Logger, HealthDataPushEvent } from '@veepoo/vpble-sdk';
import { BleDevice } from '@veepoo/vpble-sdk';
import { router } from '@kit.ArkUI';
import { preferences, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

@Entry
@Component
struct Index {
  // --- UI 状态 ---
  @State connectionState: ConnectionState = ConnectionState.UNINITIALIZED;
  @State toastMsg: string = '';
  @State showToast: boolean = false;

  // --- 设备信息显示 ---
  @State connectedDeviceName: string = '--';
  @State deviceMac: string = '--';
  @State firmwareVersion: string = '--';
  @State batteryLevel: string = '--';
  @State stepInfo: string = '--';

  // --- 重连机制 ---
  @State isReconnecting: boolean = false;
  @State reconnectAttempts: number = 0;
  private lastConnectedDevice: BleDevice | null = null;
  private isUserDisconnect: boolean = false;
  private reconnectTimer: number = -1;
  private toastTimer: number = -1;
  private static readonly MAX_RECONNECT_ATTEMPTS: number = 5;
  private static readonly RECONNECT_INTERVAL_MS: number = 3000;

  // --- 持久化存储 ---
  private preferences: preferences.Preferences | null = null;
  private static readonly PREF_NAME: string = 'vpble_reconnect';
  private static readonly KEY_DEVICE_JSON: string = 'last_device';

  // --- 日志 ---
  @State logMessages: string[] = [];
  logScroll: Scroller = new Scroller();

  // --- 步数查询节流 ---
  private lastStepQueryMs: number = 0;
  private static readonly STEP_QUERY_MIN_INTERVAL_MS: number = 5000;

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Text('VPBleSDK')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
          Text(SDK_VERSION)
            .fontSize(14)
            .fontColor('#999999')
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 4, bottom: 4 })

        // 按钮区域: 设备扫描 + 断开连接
        Row() {
          Button('设备扫描')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#007DFF')
            .borderRadius(8)
            .layoutWeight(1)
            .height(36)
            .enabled(this.connectionState === ConnectionState.READY ||
              this.connectionState === ConnectionState.DISCONNECTED)
            .opacity((this.connectionState === ConnectionState.READY ||
              this.connectionState === ConnectionState.DISCONNECTED) ? 1 : 0.4)
            .onClick(() => this.goToScanPage())

          Blank().width(16)

          Button('断开连接')
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#E84026')
            .borderRadius(8)
            .layoutWeight(1)
            .height(36)
            .enabled(this.isBleConnected())
            .opacity(this.isBleConnected() ? 1 : 0.4)
            .onClick(() => this.disconnect())
        }
        .width('100%')
        .margin({ bottom: 6 })

        // 设备信息卡片
        this.DeviceInfoCard()

        // 功能按钮区域
        this.FuncButtonArea()

        // 重连状态
        if (this.isReconnecting) {
          Text(`重连中... (${this.reconnectAttempts}/${Index.MAX_RECONNECT_ATTEMPTS})`)
            .fontSize(13)
            .fontColor('#FF9800')
            .margin({ top: 12 })
        }

        // 日志区域
        this.LogSection()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })

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
    .backgroundColor('#F5F5F5')
  }

  aboutToAppear(): void {
    this.initSDK()
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  // ==================== 设备信息卡片 ====================

  @Builder
  DeviceInfoCard() {
    Column() {
      // 第一行: 设备名称 + MAC地址
      Row() {
        Column() {
          Text('设备名称')
            .fontSize(11)
            .fontColor('#999999')
          Text(this.connectedDeviceName)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider()
          .vertical(true)
          .height(28)
          .color('#F0F0F0')

        Column() {
          Text('MAC地址')
            .fontSize(11)
            .fontColor('#999999')
          Text(this.deviceMac)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })

      // 第二行: 固件版本 + 电池电量
      Row() {
        Column() {
          Text('固件版本')
            .fontSize(11)
            .fontColor('#999999')
          Text(this.firmwareVersion)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider()
          .vertical(true)
          .height(28)
          .color('#F0F0F0')

        Column() {
          Text('电池电量')
            .fontSize(11)
            .fontColor('#999999')
          Text(this.batteryLevel)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color('#F0F0F0').margin({ top: 10, bottom: 10 })

      // 第三行: 实时步数
      Column() {
        Text('实时步数')
          .fontSize(11)
          .fontColor('#999999')
        Text(this.stepInfo)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Color.White)
    .borderRadius(12)
  }

  // ==================== 功能按钮区域 ====================

  @Builder
  FuncButtonArea() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignContent: FlexAlign.Start }) {
      this.FuncButton('睡眠', 'pages/subPages/SleepPage')
      this.FuncButton('日常数据', 'pages/subPages/DailyDataPage')
      this.FuncButton('运动数据', 'pages/subPages/SportPage')
      this.FuncButton('自动监测', 'pages/subPages/SwitchPage')
      this.FuncButton('单位设置', 'pages/subPages/UnitPage')
      this.FuncButton('消息通知', 'pages/subPages/MsgPage')
      this.FuncButton('BT管理', 'pages/subPages/BtPage')
      this.FuncButton('定时测量', 'pages/subPages/AutoMeasurePage')
      this.FuncButton('单项测量', 'pages/subPages/SingleMeasurePage')
      this.FuncButton('ECG心电', 'pages/subPages/EcgPage')
      this.FuncButton('微体检', 'pages/subPages/HealthGlancePage')
      this.FuncButton('设备控制', 'pages/subPages/DeviceControlPage')
      this.FuncButton('天气', 'pages/subPages/WeatherPage')
      this.FuncButton('联系人', 'pages/subPages/ContactPage')
      this.FuncButton('文字闹钟', 'pages/subPages/AlarmClockPage')
      this.FuncButton('世界时钟', 'pages/subPages/WorldClockPage')
      this.FuncButton('提醒设置', 'pages/subPages/ReminderPage')
      this.FuncButton('女性周期', 'pages/subPages/WomenPage')
      this.FuncButton('设备信息', 'pages/subPages/DevicePage')
      this.FuncButton('授权认证', 'pages/subPages/AuthPage')
      this.FuncButton('表盘与UI', 'pages/subPages/DialPage')
      this.FuncButton('固件升级', 'pages/subPages/OtaPage')
      this.FuncButton('特殊设备', 'pages/subPages/SpecialDevicePage')
      this.FuncButton('门控验证', 'pages/subPages/GatingDebugPage')
    }
    .width('100%')
    .margin({ top: 8 })
  }

  @Builder
  FuncButton(label: string, pageUrl: string) {
    Button() {
      Text(label)
        .fontSize(13)
        .minFontSize(9)
        .maxFontSize(13)
        .maxLines(1)
        .fontColor('#333333')
    }
    .backgroundColor('#DDDDDD')
    .borderRadius(8)
    .width('24%')
    .height(36)
    .margin({ right: '1%', bottom: 8 })
    .onClick(() => this.goToPageIfConnected(pageUrl))
  }

  // ==================== 日志区域 ====================

  @Builder
  LogSection() {
    Column() {
      Row() {
        Text('Log')
          .fontSize(14)
          .fontColor('#999999')
          .layoutWeight(1)
        Button('分享日志')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#666666')
          .borderRadius(4)
          .height(24)
          .padding({ left: 10, right: 10 })
          .onClick(() => { this.shareLogs(); })
      }
      .width('100%')
      .margin({ top: 16, bottom: 8 })

      Scroll(this.logScroll) {
        Column() {
          ForEach(this.logMessages, (msg: string, index: number) => {
            Text(msg)
              .fontSize(11)
              .fontColor('#666666')
              .fontFamily('monospace')
              .width('100%')
              .padding({ top: 2, bottom: 2 })
          }, (msg: string, index: number) => `${index}`)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .padding(8)
      .backgroundColor(Color.White)
      .borderRadius(8)
    }
    .width('100%')
    .layoutWeight(1)
  }

  // ==================== 操作方法 ====================

  private initSDK(): void {
    this.addLog('Initializing VPBleSDK...');

    const sdk = VPBleSDK.getInstance();
    const initResult: SDKResult = sdk.init({
      debugMode: true,
      context: getContext(this) as common.UIAbilityContext,
      logging: {
        enable: true,
        level: LogLevel.INFO,
        consoleOutput: true,
      },
    });

    if (!initResult.success) {
      this.addLog(`SDK init failed: ${initResult.error?.message}`);
      return;
    }

    // 监听连接状态变化
    sdk.on(SDKEventType.CONNECTION_STATE_CHANGED, (data: ESObject) => {
      this.connectionState = data.newState as ConnectionState;
      this.addLog(`State: → ${this.sdkStateToString(data.newState as ConnectionState)}`);

      if (data.newState === ConnectionState.DISCONNECTED) {
        this.resetDeviceInfo();
        this.tryAutoReconnect();
      } else if (data.newState === ConnectionState.CONNECTED) {
        this.cancelReconnect();
        const dev = VPBleSDK.getInstance().getConnectedDevice();
        if (dev) {
          this.lastConnectedDevice = {
            deviceId: dev.deviceId,
            mac: dev.mac,
            deviceName: dev.deviceName,
            rssi: dev.rssi,
            connectable: dev.connectable,
          };
          this.deviceDidConnected(this.lastConnectedDevice);
        }
      }
    });

    // 监听设备信息推送（电量等）
    sdk.on(SDKEventType.DEVICE_INFO, (_data: ESObject) => {
      this.updateDeviceInfo();
    });

    // 监听健康数据推送（设备主动上报 → 刷新首页步数）。
    // 注意：getStepData 的响应帧自身也会以 type='step' 从 HEALTH_DATA 冒出，
    // 若无条件回查会形成"查询→响应→再查询"自激励环路（实测 ~30ms/次打满链路），
    // 且测量类页面打开时设备变忙、响应延迟至秒级。故：跳过 step 回声 + 5s 节流。
    sdk.on(SDKEventType.HEALTH_DATA, (data: ESObject) => {
      const ev = data as HealthDataPushEvent;
      if (ev.type === 'step') {
        return;
      }
      this.queryStepDataThrottled();
    });

    sdk.on(SDKEventType.TRANSPORT_ERROR, (data: ESObject) => {
      this.addLog(`[TRANSPORT_ERROR] ${JSON.stringify(data)}`);
    });

    this.connectionState = ConnectionState.READY;
    this.addLog('SDK initialized');
    this.initPreferences();
  }

  private resetDeviceInfo(): void {
    this.connectedDeviceName = '--';
    this.deviceMac = '--';
    this.firmwareVersion = '--';
    this.batteryLevel = '--';
    this.stepInfo = '--';
  }

  private updateDeviceInfo(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    if (!dev) {
      return;
    }
    if (dev.deviceName) {
      this.connectedDeviceName = dev.deviceName;
    }
    if (dev.mac) {
      this.deviceMac = dev.mac;
    }
    if (dev.deviceFullVersion) {
      this.firmwareVersion = dev.deviceFullVersion + "-" + dev.deviceNumber;
    }
    if (dev.batteryLevel >= 0) {
      this.batteryLevel = `${dev.batteryLevel}%`;
    }

    this.addLog(`bloodOxygen = ${dev.featureList?.bloodOxygen}`)
    this.addLog(`unitSystem = ${dev.switchConfig?.unitSystem}`)
    this.addLog(`call = ${dev.msgSwitchConfig?.call}`)
    this.addLog(`bt = ${dev.hasBt ? "有" : "无"}, ${dev.btStatus?.btState}`)
  }

  /** 节流版步数查询：两次查询间隔 >= 5s，防推送风暴下高频轮询设备 */
  private queryStepDataThrottled(): void {
    const now = Date.now();
    if (now - this.lastStepQueryMs < Index.STEP_QUERY_MIN_INTERVAL_MS) {
      return;
    }
    this.lastStepQueryMs = now;
    this.queryStepData();
  }

  private queryStepData(): void {
    VPBleSDK.getInstance().healthService.getStepData().then((result) => {
      if (result.success && result.data) {
        const steps = result.data.steps;
        // getStepData 返回协议原始值：距离=米 / 热量=0.1kcal，显示层换算 km/kcal
        const distanceKm = (result.data.distance / 1000).toFixed(3);
        const calories = (result.data.calories / 10).toFixed(1);
        this.stepInfo = `${steps}步  ${distanceKm}km  ${calories}kcal`;
        this.addLog(`Steps: ${steps}步, ${distanceKm}km, ${calories}kcal`);
      }
    }).catch((err: Error) => {
      this.addLog(`[WARN] Query steps failed: ${err.message}`);
    });
  }

  private goToScanPage(): void {
    if (this.isBleConnected()) {
      this.showToastMsg('请先断开当前设备');
      return;
    }
    router.pushUrl({ url: 'pages/subPages/ScanPage' });
  }

  private goToPageIfConnected(pageUrl: string): void {
    if (!this.isBleConnected()) {
      this.showToastMsg('设备未连接');
      return;
    }
    router.pushUrl({ url: pageUrl });
  }

  private disconnect(): void {
    this.isUserDisconnect = true;
    this.cancelReconnect();
    this.clearDeviceFromPreferences();
    this.addLog('Disconnecting...');
    VPBleSDK.getInstance().disconnect();
  }

  private deviceDidConnected(device: BleDevice): void {
    this.saveDeviceToPreferences(device);
    this.updateDeviceInfo();
    this.syncPersonalInfo().then(() => {
      this.queryStepData()
    });
  }

  private syncPersonalInfo(): Promise<void> {
    const profile: UserProfile = {
      gender: 1,
      age: 25,
      height: 175,
      weight: 70,
    };
    const goal: GoalConfig = {
      stepGoal: 10000,
      sleepGoalMinutes: 480,
      distanceGoal: 8000,
      calorieGoal: 300,
    };

    this.addLog('Syncing personal info...');
    return VPBleSDK.getInstance().configService.syncPersonalInfo(profile, goal).then((result) => {
      if (result.success) {
        this.addLog('Personal info synced');
      } else {
        this.addLog(`[WARN] Sync failed: ${result.errorMessage}`);
      }
    }).catch((err: Error) => {
      this.addLog(`[ERROR] Sync error: ${err.message}`);
    });
  }

  // ==================== 重连机制 ====================

  private initPreferences(): void {
    const context = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(context, Index.PREF_NAME).then((prefs: preferences.Preferences) => {
      this.preferences = prefs;
      this.tryRestoreDevice();
    }).catch((err: Error) => {
      this.addLog(`[WARN] Preferences init failed: ${err.message}`);
    });
  }

  private saveDeviceToPreferences(device: BleDevice): void {
    if (!this.preferences) {
      return;
    }
    const json = JSON.stringify({
      deviceId: device.deviceId,
      mac: device.mac,
      deviceName: device.deviceName,
      rssi: device.rssi,
      connectable: device.connectable,
    });
    this.preferences.put(Index.KEY_DEVICE_JSON, json);
    this.preferences.flush();
  }

  private clearDeviceFromPreferences(): void {
    if (!this.preferences) {
      return;
    }
    this.preferences.delete(Index.KEY_DEVICE_JSON);
    this.preferences.flush();
  }

  private tryRestoreDevice(): void {
    if (!this.preferences) {
      return;
    }
    const json = this.preferences.getSync(Index.KEY_DEVICE_JSON, '') as string;
    if (!json) {
      return;
    }
    try {
      const obj = JSON.parse(json) as Record<string, Object>;
      const device: BleDevice = {
        deviceId: obj['deviceId'] as string,
        mac: obj['mac'] as string,
        deviceName: obj['deviceName'] as string,
        rssi: obj['rssi'] as number,
        connectable: obj['connectable'] as boolean,
      };
      this.lastConnectedDevice = device;
      this.addLog(`Restored device: ${device.deviceName} (${device.deviceId})`);
      this.connectDevice(device);
    } catch (err) {
      this.addLog(`[WARN] Restore device failed: ${JSON.stringify(err)}`);
      this.clearDeviceFromPreferences();
    }
  }

  private connectDevice(device: BleDevice): void {
    this.lastConnectedDevice = device;
    this.connectedDeviceName = device.deviceName;
    this.addLog(`Connecting to ${device.deviceName} (${device.deviceId})...`);

    VPBleSDK.getInstance().connectDevice(device).then(() => {
      this.addLog(`Connected to ${device.deviceName}`);
    }).catch((err: Error) => {
      this.addLog(`Connection failed: ${err.message}`);
      this.connectedDeviceName = '--';
      this.tryAutoReconnect();
    });
  }

  private tryAutoReconnect(): void {
    if (this.isReconnecting) {
      return;
    }
    if (this.isUserDisconnect) {
      this.isUserDisconnect = false;
      this.addLog('User disconnect, skip auto-reconnect');
      return;
    }
    if (!this.lastConnectedDevice) {
      return;
    }
    if (this.reconnectAttempts >= Index.MAX_RECONNECT_ATTEMPTS) {
      this.addLog('Max reconnect attempts reached');
      this.cancelReconnect();
      return;
    }

    this.reconnectAttempts++;
    this.isReconnecting = true;
    this.addLog(`Auto-reconnect ${this.reconnectAttempts}/${Index.MAX_RECONNECT_ATTEMPTS}...`);

    this.reconnectTimer = setTimeout(() => {
      if (!this.lastConnectedDevice) {
        this.cancelReconnect();
        return;
      }
      VPBleSDK.getInstance().connectDevice(this.lastConnectedDevice!).then(() => {
        this.addLog(`Reconnected to ${this.lastConnectedDevice!.deviceName}`);
        this.saveDeviceToPreferences(this.lastConnectedDevice!);
      }).catch((err: Error) => {
        this.addLog(`Reconnect failed: ${err.message}`);
        this.tryAutoReconnect();
      });
    }, Index.RECONNECT_INTERVAL_MS);
  }

  private cancelReconnect(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.isReconnecting = false;
    this.reconnectAttempts = 0;
  }

  // ==================== 工具方法 ====================

  private isBleConnected(): boolean {
    return this.connectionState === ConnectionState.CONNECTED;
  }

  private addLog(msg: string): void {
    const time = new Date().toLocaleTimeString();
    this.logMessages.push(`[${time}] ${msg}`);
    if (this.logMessages.length > 100) {
      this.logMessages.shift();
    }
    setTimeout(() => {
      this.logScroll.scrollEdge(Edge.Bottom);
    }, 50);
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

  private sdkStateToString(state: ConnectionState): string {
    switch (state) {
      case ConnectionState.UNINITIALIZED: return 'Not initialized';
      case ConnectionState.READY: return 'Ready';
      case ConnectionState.BINDING: return 'Binding';
      case ConnectionState.CONNECTED: return 'Connected';
      case ConnectionState.DISCONNECTING: return 'Disconnecting';
      case ConnectionState.DISCONNECTED: return 'Disconnected';
      default: return 'Unknown';
    }
  }

  // ==================== 日志分享 ====================

  /**
   * 把当前所有 vpble.log* 合并为单个 txt，调起系统分享面板（微信/QQ 等）
   *
   * 流程：flush → 直接从 logDir 读取 vpble.log* → 按"旧→新"顺序合并为 vpble-logs.txt
   *      → systemShare.ShareController 弹分享面板
   */
  private async shareLogs(): Promise<void> {
    const logDir = Logger.getLogDir();
    if (!logDir) {
      this.showToastMsg('文件日志未启用');
      return;
    }
    this.addLog(`logDir=${logDir}`);

    // 先 flush 确保 SDK 内部 buffer 都落盘
    await Logger.flush();

    // 校验 logDir 存在；缺失则逐级补建（兜底旧版 SDK 未真正创建目录的场景）
    this._ensureLogDir(logDir);

    const context = getContext(this) as common.UIAbilityContext;
    const shareDir = `${context.cacheDir}/vpble-share-${Date.now()}`;

    try {
      fs.mkdirSync(shareDir, true);
      this.addLog(`shareDir=${shareDir}`);

      // 直接列出 logDir，不走 Logger.exportLogs
      let srcFiles: string[] = [];
      try {
        const all: string[] = fs.listFileSync(logDir);
        this.addLog(`logDir 条目 ${all.length} 个: ${all.join(',')}`);
        srcFiles = all
          .filter((name: string) => name.startsWith('vpble.log'))
          .sort((a: string, b: string) => this._logFileOrder(b) - this._logFileOrder(a));
      } catch (err) {
        const e = err as BusinessError;
        this.showToastMsg(`扫描 logDir 失败: ${e.message}`);
        this.addLog(`[ERROR] 扫描失败: code=${e.code}, msg=${e.message}`);
        return;
      }

      if (srcFiles.length === 0) {
        this.showToastMsg('暂无日志');
        return;
      }
      this.addLog(`待合并 ${srcFiles.length} 个文件`);

      const decoder = util.TextDecoder.create('utf-8');
      let merged = '';
      for (const name of srcFiles) {
        const path = `${logDir}/${name}`;
        try {
          const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
          const stat = fs.statSync(path);
          const buf = new ArrayBuffer(stat.size);
          fs.readSync(file.fd, buf);
          fs.closeSync(file.fd);
          merged += `===== ${name} =====\n`;
          merged += decoder.decodeWithStream(new Uint8Array(buf));
          merged += '\n';
        } catch (err) {
          const e = err as BusinessError;
          this.addLog(`[WARN] 读 ${name} 失败: code=${e.code}, msg=${e.message}`);
        }
      }

      const mergedPath = `${shareDir}/vpble-logs.txt`;
      const outFile = fs.openSync(mergedPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(outFile.fd, merged);
      } finally {
        fs.closeSync(outFile.fd);
      }
      this.addLog(`已生成 vpble-logs.txt (${merged.length} 字符)`);

      // 调起系统分享面板
      const utdTypeId: string = utd.getUniformDataTypeByFilenameExtension('.txt', utd.UniformDataType.TEXT);
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: fileUri.getUriFromPath(mergedPath),
        title: 'VPBleSDK 日志',
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      const uiContext = this.getUIContext();
      const abilityContext = uiContext.getHostContext() as common.UIAbilityContext;
      await controller.show(abilityContext, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE,
      });
      this.addLog('已调起分享面板');
    } catch (err) {
      const e = err as BusinessError;
      this.showToastMsg(`分享失败: ${e.message ?? JSON.stringify(err)}`);
      this.addLog(`[ERROR] 分享失败: code=${e.code}, msg=${e.message}`);
    }
  }

  /**
   * 兜底：用 statSync 校验 logDir，缺失则逐级创建。
   *
   * accessSync 在部分 HarmonyOS 版本对多层缺失路径返回结果不可靠，
   * 用 statSync 是为了准确判断；逐级 mkdir 是绕开 mkdirSync(recursion) 不真正递归的问题。
   */
  private _ensureLogDir(logDir: string): void {
    let isDir = false;
    try {
      const stat = fs.statSync(logDir);
      isDir = stat.isDirectory();
    } catch (_e) {
      isDir = false;
    }
    if (isDir) {
      return;
    }
    this.addLog(`[WARN] logDir 不存在，尝试补建`);
    const parts: string[] = logDir.split('/').filter((p: string) => p.length > 0);
    let current: string = '';
    for (const part of parts) {
      current = current ? `${current}/${part}` : `/${part}`;
      try {
        const s = fs.statSync(current);
        if (!s.isDirectory()) {
          this.addLog(`[ERROR] 路径已存在但非目录: ${current}`);
          return;
        }
      } catch (_e) {
        try {
          fs.mkdirSync(current, true);
        } catch (err) {
          this.addLog(`[ERROR] 创建 ${current} 失败: ${(err as BusinessError).message}`);
          return;
        }
      }
    }
    this.addLog('logDir 补建完成');
  }

  /** 日志文件排序键：vpble.log → -1（最新），vpble.log.N → N */
  private _logFileOrder(name: string): number {
    if (name === 'vpble.log') {
      return -1;
    }
    const parts = name.split('.');
    const last = parts[parts.length - 1];
    const n = parseInt(last, 10);
    return isNaN(n) ? -1 : n;
  }
}

# 集成指南

完整集成说明。新手建议先看 [QUICKSTART.md](QUICKSTART.md)。本文深入到依赖机制、各能力入口与常见报错。

## 1. 概述

VPBleSDK 是 Veepoo 手环的鸿蒙 BLE 协议栈,以 HAR 形态交付。一条 GATT 连接承载所有协议,按特征 UUID 分用(Veepoo 私有协议 + JieLi RCSP)。

集成方职责:**驱动 BLE 扫描**、调用 SDK `connectDevice`、按业务读数据/订阅事件。SDK 内部自管 MTU、服务发现、特征订阅、写队列、密钥认证。

## 2. 包内容

集成方只需 **1 个** HAR:`dist/veepoo-vpble-sdk-1.1.0.har`(VPBleSDK 主体)。它是**自包含**的——6 个杰理(JieLi)HAR 已打入其内部 `libs/`,ohpm 会自动作为传递依赖拉取,无需集成方声明。`dist/har/` 另附这 6 个杰理 HAR 仅供查阅/替换:

| 文件 | 包名 | 用途 | 是否需集成方声明 |
|---|---|---|---|
| `veepoo-vpble-sdk-1.1.0.har` | **`@veepoo/vpble-sdk`** | VPBleSDK 主体(单例 + 31 领域服务) | ✅ 唯一需声明 |
| `JL_RCSP_HEALTH_*.har` | `jl_rcsp` | 杰理 RCSP 协议核心 | ❌(已内含) |
| `JL_OTA_HEALTH_*.har` | `jl_ota` | 杰理 OTA | ❌ |
| `JL_RCSP_OP_HEALTH_*.har` | `jl_rcsp_op` | 杰理 RCSP 操作 | ❌ |
| `JL_RCSP_Util_HEALTH_*.har` | `jl_rcsp_util` | 杰理 RCSP 工具 | ❌ |
| `JL_BmpConvert_*.har` | `bmpconvert` | 位图转换(表盘背景) | ❌ |
| `library_par.har` | `library_par` | PAR 序列化 | ❌ |

## 3. ⚠️ 集成关键点

### 3.1 依赖键必须叫 `@veepoo/vpble-sdk`

VPBleSDK HAR 的内部包名(`oh-package.json5` 的 `name`)是 **`@veepoo/vpble-sdk`**(scoped 命名,防与其他包冲突)。OHPM 强制依赖键 == 包内部名(不一致报 `Inconsistent Dep Names`),因此你工程里的依赖**键**必须是 `@veepoo/vpble-sdk`:

```json5
// ✅ 正确
"@veepoo/vpble-sdk": "file:libs/veepoo-vpble-sdk-1.1.0.har"
// ❌ 错误(键名不符 → "Inconsistent Dep Names" / "package not found")
"vpsdk": "file:libs/veepoo-vpble-sdk-1.1.0.har"
```

文件名可随意(带版本号便于管理),但键 + `import from` 都必须是 `@veepoo/vpble-sdk`。

### 3.2 不要额外声明 6 个杰理 HAR

SDK HAR 已自包含(杰理 HAR 在其内部 `libs/`)。**只声明 `"@veepoo/vpble-sdk"` 一个依赖即可**;再额外声明 6 个杰理 HAR 会与 SDK 自带的版本冲突。

> 若使用了旧版非自包含 HAR,或额外声明了这 6 个杰理 HAR,可能出现 `ohpm install` 失败或运行时 `cannot find record` 崩溃。处理见 [§12 常见报错排查](#12-常见报错排查)。

唯一依赖声明见 [QUICKSTART.md §1](QUICKSTART.md)。

## 4. 前置与权限

- DevEco Studio(自带 hvigorw / ohpm / SDK)
- `compatibleSdkVersion 5.0.0(12)`、`targetSdkVersion 6.0.2(22)`
- 权限:`ACCESS_BLUETOOTH`、`APPROXIMATELY_LOCATION`、`LOCATION`(蓝牙扫描需定位)。详见 [PERMISSIONS.md](PERMISSIONS.md)。
- 设备:支持 Veepoo 手环(广播厂商 ID `0xF8F8`)

## 5. 初始化

在 `EntryAbility.onWindowStageCreate` 调一次 `init`(重复调用返回 `ALREADY_INITIALIZED`,需先 `destroy()`):

```ts
const config: SDKConfig = {
  context: this.context,            // 可选:用于 <filesDir>/vpble/log 落盘
  debugMode: true,                  // 详细 BLE/RCSP 报文日志
  logging: { enable: true, level: LogLevel.DEBUG, consoleOutput: true },
  // mtuSize?, requestTimeout?(默认 5000ms), maxRetries?(默认 3), enableEncryption?
};
VPBleSDK.getInstance().init(config);
```

`SDKConfig` 字段全部可选,最小化集成只需 `{ context }`(甚至 context 也可省)。

## 6. 扫描(宿主驱动)

SDK 不持有扫描器。集成方调鸿蒙 `ble.startBLEScan` + `ble.on('BLEDeviceFind')`,把原始 `ScanResult[]` 喂给 `processScanResults`(纯解析:命中 `0xF8F8`、名称非空、解析真实 MAC,无副作用):

```ts
const cb = (data: Array<ble.ScanResult>) => {
  const found: BleDevice[] = VPBleSDK.getInstance().processScanResults(data);
  // 自行按 deviceId 去重后展示
};
ble.on('BLEDeviceFind', cb);
ble.startBLEScan([{ manufactureId: 0xF8F8 }], { interval: 100, dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY, matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE });
```

## 7. 连接

`connectDevice(device)` 返回 `Promise<SDKResult>`。一次调用内聚完成:**GATT 连接 → MTU 协商 → 服务发现 → 特征 notify 订阅 → 密钥认证 → 特性位/电量读取**。`res.success === true` 即已认证可通信。

```ts
VPBleSDK.getInstance().connectDevice(device)
  .then((res: SDKResult) => { /* res.success */ })
  .catch((err: Error) => { /* 状态机拒绝:上次未断开,先 disconnect 再重试 */ });
```

连接成功后 `getConnectedDevice()` 返回 `VPDevice`(含 `mac`、`featureList`、版本号、电量快照等,无需再单独取设备信息)。

**做重连策略时**(1.1.0 新增):`getState()` 在整个 `BINDING` 阶段都不变,分不清「原生链路没连上」和「已连上、正在跑初始化」。用 `isNativeLinkUp()` 区分——返回 `false` 说明目标地址不可达,该换一条建链路径(如重新扫描拿新的 `deviceId`);返回 `true` 只是初始化慢,继续等即可。

另有 `setConnectionConfirmation(isNeed)`:置 `true` 时支持该功能的设备会在连接前弹确认框。通常扫描页主动发起的连接传 `true`,后台自动重连传 `false`。需在 `connectDevice()` 之前设置。

## 8. 读数据(按领域服务)

服务通过 **getter 属性**访问(注意是属性,不是方法):`VPBleSDK.getInstance().deviceService.getBatteryInfo()`。常用:

```ts
const sdk = VPBleSDK.getInstance();
sdk.deviceService.getBatteryInfo()             // → Promise<BatteryInfoResult>
sdk.healthService.getStepData(HealthQueryDay.TODAY)        // → Promise<StepDataResult>
sdk.healthService.getSleepData(HealthQueryDay.TODAY)       // → Promise<SleepDataResult>
sdk.healthService.getHealthData(day, position, onProgress) // → Promise<HealthDataResult>
sdk.heartRateService.startMeasurement(...)     // 实时心率测量
```

31 个服务及代表方法见 [API.md](API.md)。返回结构统一为 `{ success, data?, errorMessage? }` 或 `SDKResult { success, error? }`。

## 9. 订阅事件

设备主动上报(电量变更、断连、报警变更、OTA 进度…)经事件总线推送:

```ts
const cb = (data: ESObject) => { /* 处理 */ };
VPBleSDK.getInstance().on(SDKEventType.BATTERY_UPDATE, cb);
// 离开时:VPBleSDK.getInstance().off(SDKEventType.BATTERY_UPDATE, cb);
```

`SDKEventType` 全集(26 项):

| 事件 | 含义 |
|---|---|
| `CONNECTION_STATE_CHANGED` | 连接状态变更(载荷 `{oldState, newState}`) |
| `BATTERY_UPDATE` | 电量更新 |
| `DEVICE_INFO` / `HEALTH_DATA` | 设备信息 / 健康数据 |
| `FIND_DEVICE_STATE` / `FIND_PHONE_REQUEST` | 查找设备 / 查找手机 |
| `PHOTO_CONTROL` | 拍照控制 |
| `SCREEN_BRIGHT_CHANGED` / `RAISE_TO_WAKE_CHANGED` | 屏幕亮度 / 抬腕亮屏变更 |
| `ALARM_CHANGED` / `REMINDER_CHANGED` | 闹钟 / 提醒变更 |
| `HEALTH_ALARM_CHANGED` / `SPO2_AUTO_CHANGED` | 健康报警 / 血氧自动监测变更 |
| `UI_STYLE_CHANGED` | 表盘 UI 样式变更 |
| `FOURG_SERVICE_CHANGED` / `BT_STATUS_CHANGED` | 4G / 蓝牙通话状态 |
| `MESSAGE` / `ALERT` | 消息 / 告警 |
| `CONFIG_CHANGED` / `MSG_SWITCH_CHANGED` | 配置 / 消息开关变更 |
| `RCSP_INIT_COMPLETE` / `RCSP_MANDATORY_UPGRADE` | RCSP 初始化完成 / 强制升级 |
| `OTA_PROGRESS` | OTA 进度 |
| `HEALTH_ASSISTANCE` | 健康辅助 |
| `PROTOCOL_ERROR` / `TRANSPORT_ERROR` | 协议错误 / 传输错误 |

`ConnectionState`:`UNINITIALIZED=0 / READY=1 / BINDING=2 / CONNECTED=3 / DISCONNECTING=4 / DISCONNECTED=5`。

## 10. 日志

`debugMode=true` 或 `logging.level=DEBUG` 时,SDK 在 `<filesDir>/vpble/log/` 写按天滚动日志(完整 BLE/RCSP 报文 hex)。提报问题时附上该目录文件。

### 10.1 引流进你自己的日志系统(`LogSink`,1.1.0 新增)

SDK 的日志有**三条相互独立**的输出通道:文件落盘(`logging.enable`)、hilog(`logging.consoleOutput`)、以及外部 sink。三者互不依赖——即便前两条都关了,sink 仍会触发。

如果你已有统一日志文件,不希望多出一份 `vpble.log`,可以注册 sink 把 SDK 日志按行并进去,同时关掉 SDK 自身的落盘与 hilog:

```ts
import { VPBleSDK, SDKConfig, LogLevel, Logger, LogSink } from '@veepoo/vpble-sdk';

const sink: LogSink = (level: LogLevel, tag: string, msg: string) => {
  // 只做内存入队,不要在这里做磁盘 IO —— 该回调在 SDK 内部同步调用
  myLogger.append(level, tag, msg);
};
Logger.setSink(sink);        // 传 null 注销

VPBleSDK.getInstance().init({
  context: this.context,
  logging: { enable: false, level: LogLevel.DEBUG, consoleOutput: false },
} as SDKConfig);
```

⚠️ `Logger.setSink()` 需在 `VPBleSDK.init()` **之前**调用,否则会漏掉初始化阶段的日志。回调内抛异常会被 SDK 捕获,不影响调用栈,但仍应保证非阻塞。

保持默认(不注册 sink)即为独立落盘模式:SDK 自带 `vpble.log` 轮转,反馈问题时直接回传该文件即可。

## 11. 断开与销毁

```ts
VPBleSDK.getInstance().disconnect();   // 主动断开(GATT 释放)
// Ability 销毁时:off 掉所有事件回调 + disconnect
```

务必在页面 `aboutToDisappear` / Ability `onWindowStageDestroy` 里 `off()` 回调,避免泄漏。

## 12. 常见报错排查

| 现象 | 原因 / 处理 |
|---|---|
| 启动崩溃 `cannot find record '&bmpconvert/Index&...'` / `cannot find record '&jl_rcsp/...'` | 杰理模块未被链接进 bundle。确认只声明 `"@veepoo/vpble-sdk"` 一个依赖且用的是本交付的**自包含** HAR(内部含 `libs/`);旧版剥依赖 HAR 会触发此问题 |
| `ohpm` 警告 `dependency "jl_rcsp" has conflict versions` | 杰理 HAR 互相内嵌,ohpm 自动消解,**可忽略** |
| `ble.startBLEScan` 抛 401 | filters 必须是非空数组;且需先授予定位权限 + 蓝牙已开启 |
| `init` 返回 `ALREADY_INITIALIZED` | SDK 已初始化,先 `destroy()` 再 `init`,或单例全局只 init 一次 |
| `connectDevice` 抛 "Cannot connect in state N. Disconnect first." | 上次连接未断开。先 `disconnect()` 再重试一次 |
| 编译期 `Property 'xxx' not found in '@veepoo/vpble-sdk'` | 依赖键不是 `@veepoo/vpble-sdk`,或未用自包含 HAR |
| HAP 构建警告 `No signingConfig found` | 未配置签名,产出未签名 HAP;在 DevEco 配置签名后才能安装到设备 |
| 资源冲突警告 `page_show` / `shared_desc` 等 | 杰理 HAR 自带资源与你的同名,警告级,不影响功能 |

## 13. 版本与支持

- SDK 版本:`SDK_VERSION` 常量(见 `oh-package.json5` / HAR 内 manifest)= `VERSION` 文件。
- 变更见 [CHANGELOG.md](../CHANGELOG.md)。

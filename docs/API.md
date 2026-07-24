# API 速查

入口统一为单例 `VPBleSDK.getInstance()`。服务通过 **getter 属性**访问(属性名,非方法调用)。
完整类型签名见 HAR 内 `Index.d.ets` 及各 `*.d.ets` 声明文件(IDE 可直接跳转/补全)。

## VPBleSDK 主入口

| 成员 | 签名 | 说明 |
|---|---|---|
| `getInstance()` | `static → VPBleSDK` | 单例 |
| `init(config?)` | `→ SDKResult` | 初始化(一次性) |
| `destroy()` | `→ void` | 销毁,之后可重新 init |
| `connectDevice(device)` | `→ Promise<SDKResult>` | 连接 + 认证(内聚全流程) |
| `disconnect()` | `→ void` | 断开 |
| `processScanResults(data)` | `Array<ble.ScanResult> → BleDevice[]` | 扫描结果过滤解析(纯函数) |
| `getConnectedDevice()` | `→ VPDevice \| null` | 当前连接设备模型 |
| `getState()` | `→ ConnectionState` | 连接状态 |
| `on(event, cb)` / `off(event, cb)` | | 事件订阅/取消 |
| `hasJlRcspService()` / `isRcspInitialized()` | `→ boolean` | 杰理 RCSP 能力/状态 |
| `connectDeviceIsJL()` | `→ boolean \| null` | 当前设备是否杰理芯 |

## 29 个领域服务(getter 属性)

| 服务 getter | 代表方法 | 用途 |
|---|---|---|
| `authService` | 认证相关 | 设备密钥认证(连接时自动调用) |
| `deviceService` | `getBatteryInfo()`, `getDeviceInfo()`, `getFeatureList()` | 设备信息/电量/特性位 |
| `healthService` | `getStepData(day)`, `getSleepData(day)`, `getHealthData(day,pos,cb)`, `getMaxStorageDays()` | 步数/睡眠/健康日数据读取 |
| `heartRateService` | `startMeasurement(...)`, `stopMeasurement()`, `getAlarmThreshold(type)`, `onHeartRatePush` | 心率测量/报警阈值 |
| `bloodPressureService` | `getPrivateMode()`, 测量控制 | 血压 |
| `bloodOxygenService` | `getAutoConfig()`, `setAutoConfig()`, 测量 | 血氧 |
| `bodyTemperatureService` | `getHistory()`, 测量 | 体温 |
| `bloodSugarService` | `getSixCalibration()`, 测量/校准 | 血糖 |
| `bloodComponentsService` | `getCalibration()`, 测量/校准 | 血液成分(血脂/尿酸等) |
| `ecgService` | `getSavedId()`, `getHistory()`, 测量 | 心电 |
| `bodyCompositionService` | `getSavedIds()`, `getHistory()` | 身体成分 |
| `manualMeasurementService` | `readData()` | 手动测量(血压等结构) |
| `stressService` | 测量/读取 | 压力 |
| `skinElectricService` | 测量/读取 | 肤电 |
| `autoMeasureService` | `readConfig()`, `setConfig()` | 自动监测(周期测量)配置 |
| `alarmClockService` | 读/设/删闹钟 | 闹钟 |
| `contactService` | `add()`, `delete()`, SOS 设置 | 联系人 |
| `reminderService` | 健康/久坐提醒读设 | 提醒 |
| `weatherService` | `getInfo()`, `setForecast(...)` | 天气 |
| `worldClockService` | `add()`, `delete()` | 世界时钟 |
| `deviceControlService` | `syncTimeNow()`, `switchLanguage()`, 抬腕亮屏/屏幕亮度/查找设备/拍照/清数据/恢复出厂 | 设备控制 |
| `sportService` | `readModeCrc()`, `readData()`, 运动模式控制 | 运动 |
| `dialService` | `readMarketDial()`, `readPhotoDial()`, `transferMarketDial()`, `setCustomUIStyle()` | 表盘(市场/照片/中科 DOOG) |
| `specialDeviceService` | 4G 模块、JH58 开关 | 特殊设备能力 |
| `featureModuleService` | `getSwitches()`, `setSwitch()`(0x94 多包) | A7 功能模块开关 |
| `otaService` | OTA 升级(JieLi) | 固件升级 |
| `btService` | `connectBt()`, `onBtStatusChange()` | 蓝牙通话(经典蓝牙) |
| `messageService` | `sendCallNotify()`, `endCall()`, 通知/SMS 转发 | 消息/来电转发 |
| `configService` | `getCachedMsgSwitchConfig()`, `syncPersonalInfo()`, `setUnitValue(s)`, `getSwitchConfig()` | 用户配置/单位/消息开关 |

> 表中"代表方法"为常用入口,完整方法集与参数/返回类型以 HAR 的 `.d.ets` 声明为准。返回结构统一为 `{ success, data?, errorMessage? }` 或 `SDKResult { success, error? }`。

## 关键数据模型(节选)

- `BleDevice`:`deviceName`、`deviceId`(虚拟地址,建连用)、`mac`(真实 MAC,显示用)、`rssi`
- `BatteryInfo`:`level`(0–100,`hasPercentage` 为真时有效)、`powerMode`、`lowBattery`、`voltage`
- `VPDevice`:`mac`、`featureList`(24 项特性位)
- `SDKResult`:`{ success: boolean, error?: SDKError }`
- `SDKError`:`{ code: SDKErrorCode, message: string }`

事件类型与状态机见 [INTEGRATION.md §9](INTEGRATION.md)。

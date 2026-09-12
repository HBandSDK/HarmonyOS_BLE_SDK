# 变更记录

## 1.1.0 — 2026-09-12

新增微体检与女性生理周期两个领域服务(共 31 个),日志可引流进宿主自身日志系统,
并修复了一批连接/重连稳定性问题与数据解析问题。

### ⚠️ 破坏性变更(仅 1 处)

- **`EcgSavedIdResult.id`(`number`)→ `ids`(`number[]`)**:设备单次回包可返回多条测量 ID,
  原单值字段无法承载。迁移:`r.id` → `r.ids?.[0]`,或遍历 `r.ids` 取全部。

其余改动均向后兼容。

### 新增

- **`HealthGlanceService`(微体检)**:一次测量采集多项体征。`isSupported()` /
  `startMeasurement()` / `stopMeasurement()`,配进度、完成、错误三个监听。
- **`WomenService`(女性生理周期)**:五种状态(无状态/月经/备孕/怀孕/妈咪)的设置与读取,
  不同状态必填的日期不同。
- **`LogSink`**:经 `Logger.setSink()` 把 SDK 日志引流进宿主自身的日志系统,
  可同时关闭 SDK 自带的落盘与 hilog,实现单一统一日志文件。用法见 [INTEGRATION §10.1](docs/INTEGRATION.md)。
- **`VPBleSDK.isNativeLinkUp()`**:区分「链路尚未建立」与「链路已建立、正在初始化」,
  供上层重连策略决策(`getState()` 在整个 BINDING 阶段不变,无法区分二者)。
- **`VPBleSDK.setConnectionConfirmation(isNeed)`**:控制设备端是否弹出连接确认框。
- **`VPBleSDK.getConnectDeviceRssi(cb)`**:读取当前连接的信号强度。
- `ContactService.save()` 新增可选入参 `supportSos`(默认 `true`,旧调用方无需改动):
  传 `false` 时不下发 SOS 数据块,用于不支持 SOS 的机型。
- 血压结果新增 `privateMode`(私人模式)字段。
- 新增错误码 `SDKErrorCode.ENGINE_DESTROYED`。

### 修复

- **连接 / 重连稳定性**:清理断连后残留的请求状态与定时器,消除其对重连后指令下发的干扰;
  修复 MTU 协商阶段的空引用与回调竞态;链路已断时请求不再无效重试到超时。
- **数据解析**:修复血糖数值、ECG 记录 ID 列表、运动轨迹采样点、设备开关配置读取等多处
  解析问题;改善表盘与功能模块在不同机型上的数据下发兼容性。
- **HRV 分析**:散点图、洛伦兹星级与相似度的计算口径及生成门槛已与 iOS / Android 端对齐,
  同一设备同一份数据在三端结果一致。

### 交付面

- 补齐微体检相关类型的公开导出(1.0.0 遗漏,集成方此前拿得到实例却无法命名其类型与枚举)。
- 示例工程新增微体检、女性生理周期两页(共 36 页)。

### 说明

- 混淆仍未开启(同 1.0.0):公开符号名未混淆,后续版本计划开启。

## 1.0.0 — 2026-07-23

VPBleSDK for HarmonyOS 首个第三方交付版本。

### 交付内容
- VPBleSDK HAR:`VPBleSDK` 单例 + 29 领域服务 + RCSP 桥接 + HRV 分析器 + 完整数据模型。
- 6 个杰理(JieLi)HAR 随包:RCSP / OTA / 位图转换 / PAR 序列化。
- 可运行集成示例工程(`sdk-demo/`):扫描 → 连接 → 电量 → 事件。
- 集成文档(QUICKSTART / INTEGRATION / API / PERMISSIONS)。

### 关键集成约定
- 包名/依赖键/import 名统一为 `@veepoo/vpble-sdk`(scoped,防与其他包冲突;ohpm 强制依赖键 == 包内部名)。
- **SDK HAR 自包含**:6 个杰理 HAR 已打入其内部 `libs/`,集成方**只需声明 `"@veepoo/vpble-sdk"` 一个依赖**,ohpm 自动拉取杰理传递依赖。不要额外声明 6 个杰理(会冲突)。
- 蓝牙扫描需定位权限,且扫描由集成方驱动(`ble.startBLEScan` + `processScanResults`)。

### 已知限制 / 后续
- **混淆(首版关闭)**:公开符号名未混淆,后续版本计划开启,待公开面稳定后再启用。
- **公开面**:出货 HAR 的 `.d.ets` 仅保留类型、签名与字段名;协议实现相关的内部组件不纳入公开导出。
- 资源冲突警告:杰理 HAR 自带资源(`page_show`、`shared_desc` 等)可能与集成方同名,警告级,不影响功能。
- ArkTS API 弃用:`router.pushUrl` / `router.back` 在新版 SDK 标记弃用(demo 仍可用),后续可迁 `Navigation`。

### 许可
- VPBleSDK 由 Veepoo 授权集成方使用,以双方协议为准。
- 随包杰理 HAR 为第三方组件,Veepoo 已获其再分发授权,随 SDK 一并提供。

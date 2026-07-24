# 变更记录

## 1.0.0 — 2026-07-23

VPBleSDK for HarmonyOS 首个第三方交付版本。

### 交付内容
- VPBleSDK HAR(字节码 + `.d.ets` 声明):`VPBleSDK` 单例 + 29 领域服务 + RCSP 桥接 + HRV 分析器 + 完整数据模型。
- 6 个杰理(JieLi)HAR 随包:RCSP / OTA / 位图转换 / PAR 序列化。
- 可运行集成示例工程(`sdk-demo/`):扫描 → 连接 → 电量 → 事件。
- 集成文档(QUICKSTART / INTEGRATION / API / PERMISSIONS)。
- 打包脚本(`scripts/build-sdk-release.sh`)。

### 关键集成约定
- 包名/依赖键/import 名统一为 `@veepoo/vpble-sdk`(scoped,防与其他包冲突;ohpm 强制依赖键 == 包内部名)。
- **SDK HAR 自包含**:6 个杰理 HAR 已打入其内部 `libs/`,集成方**只需声明 `"@veepoo/vpble-sdk"` 一个依赖**,ohpm 自动拉取杰理传递依赖。不要额外声明 6 个杰理(会冲突)。
- 蓝牙扫描需定位权限,且扫描由集成方驱动(`ble.startBLEScan` + `processScanResults`)。

### 已知限制 / 后续
- **混淆(v1 首版关闭)**:HAR 字节码已无源码,但公开符号未混淆。v1.1 计划开启名称混淆 + keep-list(`newsdk/build-profile.json5` 与 `consumer-rules.txt`),待公开面稳定后再启用。
- **声明文件脱敏**:出货 HAR 的 `.d.ets` 已**剥离全部注释**(JSDoc/行注释),不含命令码(0xXX)、payload 字节布局、命令名等协议实现细节;仅保留类型/签名/字段名。协议内部件(`ProtocolEngine`/`ProtocolFrame`/`codec`/`RcspBridge`/`CommandId`)未纳入公开导出。v1.1 混淆将进一步隐藏符号名。
- 资源冲突警告:杰理 HAR 自带资源(`page_show`、`shared_desc` 等)可能与集成方同名,警告级,不影响功能。
- ArkTS API 弃用:`router.pushUrl` / `router.back` 在新版 SDK 标记弃用(demo 仍可用),后续可迁 `Navigation`。

### 许可
- VPBleSDK 由 Veepoo 授权集成方使用,以双方协议为准。
- 随包杰理 HAR 为第三方组件,Veepoo 已获其再分发授权,随 SDK 一并提供。

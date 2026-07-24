# VPBleSDK for HarmonyOS

Veepoo 手环 BLE 协议通信 SDK。通过单条 GATT 连接完成设备扫描、连接认证、健康/运动数据读取、实时测量、设备配置(表盘/闹钟/天气/通知/世界时钟)、JieLi RCSP/OTA 等全流程。

- **SDK 版本**:见 `VERSION`(当前 1.0.0)
- **平台**:HarmonyOS,compatibleSdkVersion `5.0.0(12)`,targetSdkVersion `6.0.2(22)`
- **形态**:字节码 HAR(0 源码 + `.d.ets` 类型声明),源码不外泄
- **依赖**:6 个杰理(JieLi)HAR(RCSP/OTA/位图转换/PAR 序列化),随包提供

## 本目录结构

```
dist/
├── veepoo-vpble-sdk-1.0.0.har   # 主交付物(自包含:内置 6 个杰理 HAR 于 libs/)
├── VERSION
├── CHANGELOG.md
├── har/                          # SDK HAR + 6 杰理 HAR(参考/替换用;集成只需 SDK HAR)
├── sdk-demo/                     # 可运行集成示例(34 页:扫描/连接/测量全家桶/设备配置/表盘/OTA…)
└── docs/
    ├── QUICKSTART.md             # ← 新手先看这个(5 分钟跑通)
    ├── INTEGRATION.md            # 完整集成指南(含必读的集成要点)
    ├── API.md                    # 服务 × 方法速查表
    └── PERMISSIONS.md            # 权限声明与运行时申请
```

## 快速上手

1. 读 [docs/QUICKSTART.md](docs/QUICKSTART.md),把 `veepoo-vpble-sdk-1.0.0.har` 引入你的工程。
2. 参考 `sdk-demo/` 的写法(可直接在 DevEco Studio 打开运行)。
3. 遇到问题查 [docs/INTEGRATION.md](docs/INTEGRATION.md) 的"常见报错排查"。

## ⚠️ 必读的集成要点

详见 [docs/INTEGRATION.md](docs/INTEGRATION.md),这里先点明:

1. **依赖键必须写 `"@veepoo/vpble-sdk"`**:HAR 的内部包名是 `@veepoo/vpble-sdk`(scoped,防冲突),你工程 `oh-package.json5` 里的依赖键必须就叫这个(文件名随意),否则 ohpm 报 "Inconsistent Dep Names"。
2. **SDK HAR 是自包含的,只声明 `"@veepoo/vpble-sdk"` 一个依赖**:6 个杰理(JieLi)HAR 已打入 SDK HAR 内部 `libs/`,ohpm 会自动作为传递依赖拉取。**不要**再额外声明这 6 个,否则版本冲突。

## 许可说明

- VPBleSDK:由 Veepoo 授权给集成方使用,具体条款以双方协议为准。
- 随包提供的 6 个杰理(JieLi)HAR 为第三方组件,Veepoo 已获其再分发授权,随 SDK 一并提供给集成方使用。

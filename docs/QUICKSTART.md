# 快速开始(5 分钟跑通)

目标:把 VPBleSDK 引入一个新 HarmonyOS 工程,完成 **扫描 → 连接 → 读电量 → 订阅事件**。
完整可运行版本见 `dist/sdk-demo/`(含 34 个能力页:测量全家桶/睡眠/运动/设备配置/表盘/OTA 等),本页只提炼最小闭环。

## 0. 前置

- DevEco Studio(自带 hvigorw / ohpm)
- 工程 `compatibleSdkVersion 5.0.0(12)`、`targetSdkVersion 6.0.2(22)`
- 一台 Veepoo 手环(广播厂商 ID `0xF8F8`)

## 1. 引入 SDK HAR

SDK HAR 是**自包含**的:6 个杰理(JieLi)HAR 已打入其内部 `libs/`,你只需把 **1 个** `veepoo-vpble-sdk-1.0.0.har` 复制到工程的 `<模块>/libs/`,然后在**使用 SDK 的模块**(通常是 `entry`)的 `oh-package.json5` 里声明:

```json5
{
  "name": "entry",
  // ...
  "dependencies": {
    // ⚠️ 键必须是 "@veepoo/vpble-sdk"(与 HAR 内部包名一致),文件名可随意
    "@veepoo/vpble-sdk": "file:libs/veepoo-vpble-sdk-1.0.0.har"
  }
}
```

Sync(OHPM 安装)。ohpm 会从 SDK HAR 内部 `libs/` 自动拉取 6 个杰理 HAR 作为传递依赖;它们互相内嵌会产生**版本冲突警告,自动消解**,可忽略。

> ⚠️ **不要**再额外声明 6 个杰理 HAR——会与 SDK 自带的冲突。只声明 `"@veepoo/vpble-sdk"` 一个。


## 2. 声明权限

`entry/src/main/module.json5`:

```json5
"requestPermissions": [
  { "name": "ohos.permission.ACCESS_BLUETOOTH", "reason": "$string:reason_bluetooth", "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" } },
  { "name": "ohos.permission.APPROXIMATELY_LOCATION", "reason": "$string:reason_location", "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" } },
  { "name": "ohos.permission.LOCATION", "reason": "$string:reason_location", "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" } }
]
```
> 蓝牙扫描在鸿蒙上需要定位权限。详见 [PERMISSIONS.md](PERMISSIONS.md)。

## 3. 初始化 SDK(在 EntryAbility)

```ts
import { AbilityConstant, UIAbility, Want, abilityAccessCtrl } from '@kit.AbilityKit';
import { VPBleSDK, SDKConfig, LogLevel } from '@veepoo/vpble-sdk';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage): void {
    const config: SDKConfig = {
      context: this.context,        // 可选,用于在 <filesDir>/vpble/log 落盘完整 BLE 报文
      debugMode: true,              // = logging.level=DEBUG
      logging: { enable: true, level: LogLevel.DEBUG, consoleOutput: true },
    };
    VPBleSDK.getInstance().init(config);

    // 申请蓝牙 + 定位权限(扫描前必须拿到)
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, [
      'ohos.permission.ACCESS_BLUETOOTH',
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION',
    ]);

    windowStage.loadContent('pages/Index', () => {});
  }
}
```

> **init 位置**:推荐在 Ability 启动时(`onWindowStageCreate`)init 一次,如上。示例工程 `sdk-demo` 出于自身流程在首页 `Index.aboutToAppear → initSDK()` 里 init —— 两种写法等价,**保证全局只 init 一次即可**(重复 init 返回 `ALREADY_INITIALIZED`)。

## 4. 扫描(宿主驱动)

SDK 不启动扫描,由你调用鸿蒙 `ble` API 并把原始结果喂给 `processScanResults`:

```ts
import { ble } from '@kit.ConnectivityKit';
import { VPBleSDK, BleDevice } from '@veepoo/vpble-sdk';

ble.on('BLEDeviceFind', (data: Array<ble.ScanResult>) => {
  // processScanResults 是纯过滤解析:命中 0xF8F8 且名称非空的 Veepoo 设备,并解析出真实 MAC
  const found: BleDevice[] = VPBleSDK.getInstance().processScanResults(data);
  found.forEach((d) => { /* 加入你的列表(按 d.deviceId 去重) */ });
});
// filters 必须是非空数组,按厂商 ID 0xF8F8 过滤
ble.startBLEScan([{ manufactureId: 0xF8F8 }], {
  interval: 100, dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY, matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE,
});
// 停止:ble.off('BLEDeviceFind', cb); ble.stopBLEScan();
```

## 5. 连接 + 读电量 + 订阅事件

```ts
import { VPBleSDK, BleDevice, SDKResult, SDKEventType, ConnectionState } from '@veepoo/vpble-sdk';

const onConn = (data: ESObject) => {
  const p = data as { oldState: ConnectionState; newState: ConnectionState };
  console.info(`连接状态:${p.oldState} → ${p.newState}`);
};
VPBleSDK.getInstance().on(SDKEventType.CONNECTION_STATE_CHANGED, onConn);

// connectDevice 一次性完成 GATT 连接 + MTU + 服务发现 + 特征订阅 + 密钥认证
VPBleSDK.getInstance().connectDevice(device).then((res: SDKResult) => {
  if (res.success) {
    // 读取电量
    VPBleSDK.getInstance().deviceService.getBatteryInfo().then((r) => {
      if (r.success && r.data) { console.info(`电量 ${r.data.level}%`); }
    });
  }
});

// 离开时务必 off 掉回调并 disconnect
// VPBleSDK.getInstance().off(SDKEventType.CONNECTION_STATE_CHANGED, onConn);
// VPBleSDK.getInstance().disconnect();
```

🎉 到这里你已完成最小闭环。更多能力(心率/血压/ECG/睡眠/表盘/OTA…)见 [API.md](API.md) 与 [INTEGRATION.md](INTEGRATION.md)。

# 权限说明

## 声明权限(`module.json5` → `requestPermissions`)

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.ACCESS_BLUETOOTH",
    "reason": "$string:reason_bluetooth",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.APPROXIMATELY_LOCATION",
    "reason": "$string:reason_location",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  },
  {
    "name": "ohos.permission.LOCATION",
    "reason": "$string:reason_location",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  }
]
```

| 权限 | 等级 | 用途 |
|---|---|---|
| `ACCESS_BLUETOOTH` | user_granted | BLE 连接/通信 |
| `APPROXIMATELY_LOCATION` | user_granted | BLE 扫描(粗略位置) |
| `LOCATION` | user_granted | BLE 扫描(精确位置) |

> 鸿蒙上 **BLE 扫描需要定位权限**;`ble.startBLEScan` 未授权时会抛 401。

## 后台模式(`abilities[].backgroundModes`)

如需后台保活接收推送(来电/通知转发、健康数据推送),在 Ability 上加:

```json5
"backgroundModes": ["bluetoothInteraction", "location"]
```

并按需申请 `ohos.permission.KEEP_BACKGROUND_RUNNING`(配合 `backgroundTaskManager.startBackgroundRunning`)。

## 运行时申请

`ACCESS_BLUETOOTH` / `LOCATION` 为 `user_granted`,需运行时弹窗申请。**注意**:`UIAbilityContext` 没有 `requestPermissionsFromUser`,要用 `@kit.AbilityKit` 的 `abilityAccessCtrl`:

```ts
import { abilityAccessCtrl } from '@kit.AbilityKit';

// 在 UIAbility.onWindowStageCreate 中,扫描前调用
const atManager = abilityAccessCtrl.createAtManager();
atManager.requestPermissionsFromUser(this.context, [
  'ohos.permission.ACCESS_BLUETOOTH',
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION',
]);
```

申请时机建议:**Ability 启动后立即申请**,用户授予后再触发扫描(参考 `sdk-demo/entry/src/main/ets/entryability/EntryAbility.ets`)。

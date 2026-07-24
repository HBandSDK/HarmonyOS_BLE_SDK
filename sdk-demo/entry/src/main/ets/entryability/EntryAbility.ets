import { AbilityConstant, UIAbility, Want, common, abilityAccessCtrl } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { VPBleSDK } from '@veepoo/vpble-sdk';

const DOMAIN = 0x0001;
const TAG = 'VPBleDemo';

/**
 * Demo 入口 Ability。
 *
 * 集成 VPBleSDK 的最小步骤:
 *  1. 在 entry/oh-package.json5 声明 "sdk": "file:.../veepoo-vpble-sdk-x.y.z.har"
 *     (依赖键必须写 "sdk",与 HAR 内部包名一致)以及 6 个杰理 HAR。
 *  2. 在 Ability 启动时调用一次 VPBleSDK.getInstance().init(config)。
 *  3. 申请蓝牙 / 定位权限(蓝牙扫描在鸿蒙上需要定位权限)。
 *  4. 之后在页面里扫描、连接、读数据、订阅事件。
 */
export default class EntryAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // VPBleSDK 的初始化交由首页 Index.aboutToAppear → initSDK() 完成(与 demo 设计一致,
    // 传 context + logging + 订阅连接状态)。此处不再重复 init,否则会触发 ALREADY_INITIALIZED,
    // 导致 initSDK 早退、连接状态卡 UNINITIALIZED、扫描按钮不可点。

    // —— 申请蓝牙与定位权限(扫描前必须拿到)——
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      atManager.requestPermissionsFromUser(this.context, [
        'ohos.permission.ACCESS_BLUETOOTH',
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION',
      ]);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'requestPermissionsFromUser failed: %{public}s', `${JSON.stringify(e)}`);
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err) ?? '');
      }
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageDestroy(): void {
    // 退出时断开连接,释放 GATT 资源
    try {
      VPBleSDK.getInstance().disconnect();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'disconnect on destroy: %{public}s', `${JSON.stringify(e)}`);
    }
  }
}

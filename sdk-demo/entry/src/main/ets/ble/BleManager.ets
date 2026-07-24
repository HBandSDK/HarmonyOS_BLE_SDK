import { ble, connection, hid } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BleDevice, VPBleSDK } from '@veepoo/vpble-sdk';

const TAG = 'VPBleSDK.BleManager';

/**
 * BLE 扫描管理类
 *
 * 仅负责 BLE 扫描逻辑，连接管理已移入 VPBleSDK 内部。
 */
export class BleManager {
  /** 扫描状态 */
  private _isScanning: boolean = false;

  /** 扫描发现的设备缓存（去重用） */
  private _discoveredDevices: Map<string, BleDevice> = new Map();

  /** 设备发现回调 */
  private _onDeviceFoundCallback: ((devices: BleDevice[]) => void) | null = null;

  /** HID Profile 实例，用于获取系统已连接的设备 */
  private _hidProfile: hid.HidHostProfile = hid.createHidHostProfile();

  /** 系统已连接设备定时查询 ID */
  private _systemConnectedTimer: number | null = null;

  /**
   * @param onDeviceFound 设备发现回调（可选）
   */
  constructor(onDeviceFound?: (devices: BleDevice[]) => void) {
    this._onDeviceFoundCallback = onDeviceFound ?? null;
  }

  /**
   * 开始 BLE 扫描
   *
   * 扫描结果通过 onDeviceFound 回调通知。
   * 内部对设备列表进行去重（按 deviceId）。
   */
  startScan(): void {
    if (this._isScanning) {
      console.error(`${TAG}: Scan already in progress`);
      return;
    }

    this._discoveredDevices.clear();

    try {
      ble.on('BLEDeviceFind', this._onScanResult);

      const scanOptions: ble.ScanOptions = {
        interval: 100,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE,
      };

      // 从 SDK 获取扫描过滤 UUID，构造 ScanFilter
      const uuids = VPBleSDK.getInstance().getScanFilterUUIDs();
      const filters: Array<ble.ScanFilter> = [];
      for (const uuid of uuids) {
        const f: ble.ScanFilter = { serviceUuid: uuid };
        filters.push(f);
      }

      ble.startBLEScan(filters, scanOptions);
      this._isScanning = true;
      this._startSystemConnectedCheck();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`${TAG}: startBLEScan failed: ${error.code} - ${error.message}`);
    }
  }

  /**
   * 停止 BLE 扫描
   */
  stopScan(): void {
    if (!this._isScanning) {
      return;
    }

    this._stopSystemConnectedCheck();

    try {
      ble.off('BLEDeviceFind', this._onScanResult);
      ble.stopBLEScan();
    } catch (err) {
      const error = err as BusinessError;
      console.error(`${TAG}: stopBLEScan failed: ${error.code} - ${error.message}`);
    } finally {
      this._isScanning = false;
    }
  }

  /** 是否正在扫描 */
  get isScanning(): boolean {
    return this._isScanning;
  }

  /** 获取已扫描发现的设备列表，按信号量排序 */
  getDiscoveredDevices(): BleDevice[] {
    return Array.from(this._discoveredDevices.values()).sort((a, b) => b.rssi - a.rssi);
  }

  /**
   * 开始定时查询系统已连接的设备
   *
   * 设备可能已被系统在后台连接（如 HID 配对），此时设备不会 BLE 广播，
   * 无法通过常规扫描发现。通过 HidHostProfile.getConnectedDevices()
   * 可获取这些设备的 deviceId，构造 BleDevice 后合并到扫描结果中。
   */
  private _startSystemConnectedCheck(): void {
    this._mergeSystemConnectedDevices();
    this._systemConnectedTimer = setInterval(() => {
      this._mergeSystemConnectedDevices();
    }, 500);
  }

  /** 停止定时查询系统已连接设备 */
  private _stopSystemConnectedCheck(): void {
    if (this._systemConnectedTimer !== null) {
      clearInterval(this._systemConnectedTimer);
      this._systemConnectedTimer = null;
    }
  }

  /** 查询系统已连接设备并合并到扫描结果 */
  private _mergeSystemConnectedDevices(): void {
    const devices = this._getSystemConnectedDevices();
    if (devices.length < 1) {
      return;
    }
    let changed = false;
    for (const device of devices) {
      if (!this._discoveredDevices.has(device.deviceId)) {
        this._discoveredDevices.set(device.deviceId, device);
        changed = true;
      }
    }
    if (changed && this._onDeviceFoundCallback) {
      this._onDeviceFoundCallback(this.getDiscoveredDevices());
    }
  }

  /** 通过 HID Profile 获取系统已连接的设备列表 */
  private _getSystemConnectedDevices(): BleDevice[] {
    const devices: BleDevice[] = [];
    try {
      const connectedIds: string[] = this._hidProfile.getConnectedDevices();
      if (connectedIds.length < 1) {
        return devices;
      }
      console.info(`${TAG}: Found ${connectedIds.length} system-connected device(s)`);
      for (const deviceId of connectedIds) {
        try {
          const deviceName = connection.getRemoteDeviceName(deviceId);
          devices.push({
            deviceId: deviceId,
            mac: '',
            deviceName: deviceName,
            rssi: 0,
            connectable: true,
          });
        } catch (err) {
          const error = err as BusinessError;
          console.error(`${TAG}: getRemoteDeviceName failed: ${error.code} - ${error.message}`);
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`${TAG}: getConnectedDevices failed: ${error.code} - ${error.message}`);
    }
    return devices;
  }

  /** BLE 扫描触发函数，将系统扫描结果转换为 BleDevice 后通知上层 */
  private _onScanResult = (results: Array<ble.ScanResult>): void => {
    const vpDevices = VPBleSDK.getInstance().processScanResults(results);
    if (vpDevices.length < 1) {
      return;
    }

    for (const device of vpDevices) {
      const existing = this._discoveredDevices.get(device.deviceId);
      if (!existing || existing.rssi !== device.rssi) {
        this._discoveredDevices.set(device.deviceId, device);
      }
    }

    if (this._onDeviceFoundCallback) {
      this._onDeviceFoundCallback(this.getDiscoveredDevices());
    }
  };
}
